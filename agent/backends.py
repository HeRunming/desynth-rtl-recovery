"""
backends.py —— 可插拔推理后端

架构要点(呼应之前"两者都要支持"的讨论):
上层 Agent 只依赖 InferenceBackend 接口, 不关心背后是闭源 API 还是本地模型。
  - OpenAICompatBackend: 走 OpenAI 兼容 API (你的端点 / GPT / 国内厂商都可)
  - (将来) LocalvLLMBackend: 在 H20 服务器上跑本地/自训模型, 换后端即可, Agent 不动
"""
import os, json, urllib.request, urllib.error


class InferenceBackend:
    """所有推理后端的统一接口。"""
    def complete(self, system: str, user: str, **kw) -> str:
        raise NotImplementedError


class OpenAICompatBackend(InferenceBackend):
    """OpenAI 兼容的 /chat/completions 后端。"""

    def __init__(self, base_url=None, api_key=None, model="gpt-5.5",
                 temperature=0.2, timeout=120):
        # 密钥/端点从环境变量读, 不硬编码
        self.base_url = (base_url or os.environ["LLM_BASE"]).rstrip("/")
        self.api_key = api_key or os.environ["LLM_KEY"]
        self.model = model
        self.temperature = temperature
        self.timeout = timeout

    def complete(self, system: str, user: str, **kw) -> str:
        body = {
            "model": kw.get("model", self.model),
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": kw.get("temperature", self.temperature),
        }
        data = json.dumps(body).encode()
        req = urllib.request.Request(
            f"{self.base_url}/chat/completions", data=data,
            headers={"Authorization": f"Bearer {self.api_key}",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                resp = json.loads(r.read())
            return resp["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"LLM HTTP {e.code}: {e.read()[:300]}")
