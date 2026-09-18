"""Persistent deterministic recovery with actual emitted-RTL acceptance."""
from __future__ import annotations
import fcntl
import hashlib
import json
import math
import os
import time
import tempfile
from pathlib import Path
from .detect import propose_full_adders
from .emit import emit_recovered, emit_residual, verify_residual_export
from .ir import save_json
from .jobs import JobStore
from .proof import ProofStatus, ProofStore, prove_abc, prove_exhaustive
from .recovery import RecoveryRevision


def _publish(root, release, result):
    """Keep history and replace the latest report atomically, including running."""
    save_json(release/'report.json', result)
    pending = root/'report.pending.json'
    save_json(pending, result)
    os.replace(pending, root/'report.json')
    return result


def _export_checked(revision, release, label, budget_s, *, residual=False):
    rtl = None
    proofdir = release/(label+'_verification')
    try:
        emit = emit_residual if residual else emit_recovered
        rtl = emit(revision, release/label, timeout_s=budget_s)
        ok, _ = verify_residual_export(revision, rtl, timeout_s=budget_s, artifact_dir=proofdir)
        evidence = json.loads((proofdir/'verification.json').read_text())
        if not ok:
            return False, rtl, {'stage':label, **evidence}, None
        snapshot=proofdir/'candidate.v'
        digest=evidence.get('rtl_sha256')
        if (evidence.get('proven') is not True or evidence.get('status') != 'proven'
                or evidence.get('source_hash') != revision.graph.source_hash
                or hashlib.sha256(rtl.read_bytes()).hexdigest() != digest
                or hashlib.sha256(snapshot.read_bytes()).hexdigest() != digest):
            raise ValueError('exported RTL differs from proven snapshot or proof identity')
        # Publish the proven snapshot and its recorded digest, never a newly
        # hashed mutable export that could be edited after the proof completed.
        return True, snapshot, None, digest
    except (TimeoutError, ValueError, OSError, RuntimeError) as exc:
        status = 'timeout' if isinstance(exc, TimeoutError) else ('model_error' if isinstance(exc, ValueError) else 'tool_error')
        error = {'stage':label, 'status':status, 'proven':False, 'reason':str(exc),
                 'source_hash':revision.graph.source_hash}
        proofdir.mkdir(parents=True, exist_ok=True)
        save_json(release/(label+'_export_error.json'), error)
        if not (proofdir/'verification.json').exists():
            save_json(proofdir/'verification.json', error)
        return False, rtl, error, None


def run_recovery(graph, out, *, backend='abc', budget_s=30, final_budget_s=60):
    """Resume only validated completed proofs. Failures never replace source."""
    if backend not in {'abc','exhaustive'}: raise ValueError('unsupported backend')
    root=Path(out).resolve(); root.mkdir(parents=True,exist_ok=True)
    with (root/'worker.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        identity={'schema':'m1-run/2','source_hash':graph.source_hash,'backend':backend}
        if (root/'identity.json').exists():
            if json.loads((root/'identity.json').read_text())!=identity: raise ValueError('run identity differs; choose a new directory')
        else: save_json(root/'identity.json',identity)
        started=time.monotonic()
        release=Path(tempfile.mkdtemp(prefix='release_',dir=root))
        context={**identity, 'run_id':release.name, 'candidate_budget_s':budget_s, 'final_budget_s':final_budget_s}
        _publish(root, release, {**context, 'status':'running', 'whole_design_proven':False})
        try:
            if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in (budget_s,final_budget_s)) or budget_s <= 0 or final_budget_s < 0:
                raise ValueError('candidate budget must be positive; final budget must be nonnegative and finite')
            return _run(graph, root, release, context, started, backend, budget_s, final_budget_s)
        except Exception as exc:
            return _publish(root, release, {**context, 'status':'runner_error', 'whole_design_proven':False,
                            'error_type':type(exc).__name__, 'reason':str(exc), 'elapsed_s':time.monotonic()-started})


def _run(graph, root, release, identity, started, backend, budget_s, final_budget_s):
    validation=graph.validate()
    if validation:
        result={**identity,'status':'unsupported','reasons':validation,'whole_design_proven':False}
        return _publish(root, release, result)
    revision=RecoveryRevision(graph); rows=[]; proofs=ProofStore(root/'proof_records')
    with JobStore(root/'jobs.sqlite') as jobs:
        # Exclusive advisory lock proves no other runner owns these jobs.
        jobs.recover_interrupted(reason='previous exclusive runner exited')
        candidates=propose_full_adders(graph)
        for candidate in candidates:
            reused=False; proof=None; attempt=None
            for prior in reversed(jobs.list_attempts(source_hash=graph.source_hash,candidate_hash=candidate.candidate_hash,status='proven')):
                try:
                    evidence=proofs.load(prior['result']['proof_record'])
                    revision_next=revision.accept(candidate,evidence)
                    proof=evidence; revision=revision_next; reused=True; attempt=prior
                    break
                except (OSError, ValueError, KeyError, TypeError): continue
            if proof is None:
                attempt=jobs.submit(graph.source_hash,candidate.candidate_hash,engine=backend,budget_s=budget_s,candidate_metadata=candidate.canonical())
                jobs.claim(attempt['attempt_id'])
                prove=prove_abc if backend=='abc' else prove_exhaustive
                proof=prove(graph,candidate,timeout_s=budget_s,artifact_dir=root/'attempts'/attempt['attempt_id'])
                record=proofs.save(proof)
                jobs.finish(attempt['attempt_id'],proof.status.value,{**proof.as_dict(),'proof_record':str(record)},log_paths=[str(record)])
            accepted=reused; rejection=None
            if proof.status==ProofStatus.PROVEN and not reused:
                try: revision=revision.accept(candidate,proof); accepted=True
                except ValueError as exc: rejection=str(exc)
            rows.append({'candidate_hash':candidate.candidate_hash,'status':proof.status.value,'accepted':accepted,
                         'reused':reused,'rejection':rejection,'reason':proof.reason,
                         'retained_cells':len(candidate.retained_cells),'region_cells':len(candidate.region_cells),
                         'attempt_id':attempt['attempt_id']})
            save_json(root/'checkpoint.json',revision.residual_manifest())
    revision.export(release/'annotations')
    ok,rtl,error,proven_digest=_export_checked(revision,release,'implementation',final_budget_s)
    fallback=False; failures=[] if error is None else [error]
    if not ok:
        # Return a proven source residual when possible. Failed semantic RTL
        # remains archived, but never inherits a successful export verdict.
        fallback=True; revision=RecoveryRevision(graph)
        ok,rtl,error,proven_digest=_export_checked(revision,release,'fallback',final_budget_s,residual=True)
        if error is not None: failures.append(error)
    base=revision.residual_manifest(); replaced=base['planned_replaced_cells'] if ok and not fallback else 0
    result={**identity,'status':'proven' if ok else 'unproven','whole_design_proven':ok,
            'scope':'all_outputs_and_all_state_functions','fallback':fallback,
            'candidate_count':len(rows),'proven_candidates':sum(r['status']=='proven' for r in rows),
            'accepted_candidates':len(revision.accepted) if ok else 0,'candidates':rows,
            'source_cells':base['source_cells'],'replaced_cells':replaced,
            'retained_source_cells':base['source_cells']-replaced,
            'semantic_covered_cells':base['semantic_covered_cells'] if ok else 0,
            'failures':failures,
            'rtl':str(rtl) if rtl is not None else None,
            'rtl_sha256':proven_digest if ok else (hashlib.sha256(rtl.read_bytes()).hexdigest() if rtl is not None else None),
            'verification':str(release/('fallback_verification' if fallback else 'implementation_verification')/'verification.json'),
            'elapsed_s':time.monotonic()-started}
    return _publish(root, release, result)
