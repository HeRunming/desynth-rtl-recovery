> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# 待传输文件清单 - Config A Assembly Fix

## 状态
修复已完成并通过本地测试，等待 SSH 权限恢复后传输到服务器。

## 文件
- **agent/assemble_lifted.py** (27,140 bytes)
  - 新增: `expand_cse_wires()` 函数
  - 修改: `to_v()` 签名 + 3 处调用点
  - 验证: 6 项单元测试全通过

## 传输命令
```bash
# 方式 1: base64 through SSH
base64 < agent/assemble_lifted.py | ssh hrm@140.143.244.199 \
  "base64 -d > /home/hrm/desynth/pipeline/assemble_lifted.py"

# 方式 2: scp (如果权限恢复)
scp agent/assemble_lifted.py hrm@140.143.244.199:/home/hrm/desynth/pipeline/
```

## 传输后验证流程
```bash
ssh hrm@140.143.244.199 'bash -s' << 'EOF'
cd /home/hrm/desynth
source venv/bin/activate
cd work/big

# 执行 Config A 组装
python3 ../../pipeline/assemble_lifted.py \
  --mech big_mech_cse.json \
  --names big_names.json \
  --lift big_lift.json \
  --netlist pico_big_netlist.v \
  --out pico_big_resynth.v

# 语法检查 (预期: 无 "undeclared identifier" 错误)
iverilog -t null -Wall pico_big_resynth.v 2>&1 | tee iverilog.log

# 如果通过, 执行等价验证
python3 ../../pipeline/equiv_check.py \
  --gold pico_big_netlist.v \
  --test pico_big_resynth.v \
  --cycles 1000
EOF
```

## 预期结果
✅ **修复前**: 74 个 "undeclared identifier" 错误 (未声明的 `_cN` wire)
✅ **修复后**: iverilog 无错误 (所有 `_cN` 已就地展开)

## SSH 故障排查
当前错误: `Permission denied (publickey,password)`

可能原因:
1. SSH 密钥失效或被删除
2. 服务器重启后 `~/.ssh/authorized_keys` 权限/内容变化
3. 网络策略变更

恢复方法:
- 通过其他方式登录服务器, 检查 `~/.ssh/authorized_keys`
- 或: 使用密码认证重新添加公钥
- 或: 通过跳板机/堡垒机访问
