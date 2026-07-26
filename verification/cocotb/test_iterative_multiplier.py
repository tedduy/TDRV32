"""Exercise multiplier result holding and explicit consume protocol."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


@cocotb.test()
async def all_signed_modes_and_done_hold(dut):
    dut.i_arst_n.value = 0
    dut.i_start.value = 0
    dut.i_consume.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    dut.i_alu_ctrl.value = 0xA
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await RisingEdge(dut.i_clk)
    await FallingEdge(dut.i_clk)
    dut.i_arst_n.value = 1

    vectors = [
        (0xA, 0xFFFF_FFF9, 3, 0xFFFF_FFEB),
        (0xB, 0xFFFF_FFF9, 3, 0xFFFF_FFFF),
        (0xB, 0xFFFF_FFF9, 0xFFFF_FFFD, 0),
        (0xC, 0xFFFF_FFF9, 3, 0xFFFF_FFFF),
        (0xD, 0xFFFF_FFF9, 3, 2),
    ]
    for control, operand_a, operand_b, expected in vectors:
        dut.i_operand_a.value = operand_a
        dut.i_operand_b.value = operand_b
        dut.i_alu_ctrl.value = control
        dut.i_start.value = 1
        await RisingEdge(dut.i_clk)
        await FallingEdge(dut.i_clk)
        dut.i_start.value = 0
        for _ in range(40):
            await RisingEdge(dut.i_clk)
            if int(dut.o_done.value):
                break
        assert int(dut.o_done.value)
        actual = int(dut.o_result.value)
        assert actual == expected, (
            f"control=0x{control:x} a=0x{operand_a:08x} "
            f"b=0x{operand_b:08x}: expected 0x{expected:08x}, "
            f"got 0x{actual:08x}"
        )
        await RisingEdge(dut.i_clk)  # enter and remain in DONE
        assert int(dut.o_done.value)
        assert int(dut.o_result.value) == expected
        dut.i_consume.value = 1
        await RisingEdge(dut.i_clk)
        await FallingEdge(dut.i_clk)
        dut.i_consume.value = 0
