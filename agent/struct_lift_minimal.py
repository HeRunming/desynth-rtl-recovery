"""
struct_lift_minimal.py —— assemble 阶段专用的轻量版本

只提供 assemble_lifted.py 需要的函数签名，不依赖 z3。
lift_bus() 和 z3_to_verilog() 在 assemble 阶段不会被调用
（lift 结果已经是 JSON），这里只是占位避免 import 错误。
"""


def lift_bus(*args, **kwargs):
    """占位函数 —— assemble 阶段不会调用 lift_bus"""
    raise NotImplementedError("lift_bus should not be called during assembly")


def z3_to_verilog(*args, **kwargs):
    """占位函数 —— assemble 阶段不会调用 z3_to_verilog

    lift 结果已经是 Verilog 字符串形式存在 JSON 里，不需要从 z3 对象转换。
    """
    raise NotImplementedError("z3_to_verilog should not be called during assembly")
