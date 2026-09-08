"""PyUVM qualification test for the methodology fixture."""

from __future__ import annotations

import json
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge
from pyuvm import test, uvm_test


@test()
class FlowFixtureTest(uvm_test):
    """Exercise reset, enabled updates, and disabled holds through PyUVM."""

    async def run_phase(self) -> None:
        """Drive representative operations and emit separate functional coverage."""
        self.raise_objection()
        dut = cocotb.top
        clock = Clock(dut.clk_i, 10, unit="ns")
        cocotb.start_soon(clock.start())

        # This Python coverage complements simulator-native SVA/code coverage.
        coverage = {"reset": 0, "enabled_update": 0, "disabled_hold": 0}
        dut.rst_ni.value = 0
        dut.enable_i.value = 0
        dut.data_i.value = 0
        await RisingEdge(dut.clk_i)
        await RisingEdge(dut.clk_i)
        coverage["reset"] += 1

        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 1
        dut.enable_i.value = 1
        dut.data_i.value = 0x12345678
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        assert int(dut.data_o.value) == 0x12345678
        coverage["enabled_update"] += 1

        dut.enable_i.value = 0
        dut.data_i.value = 0xDEADBEEF
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        assert int(dut.data_o.value) == 0x12345678
        coverage["disabled_hold"] += 1

        coverage_path = Path(os.environ["PYUVM_FUNCTIONAL_COVERAGE_FILE"])
        coverage_path.write_text(json.dumps(coverage, indent=2) + "\n", encoding="utf-8")
        self.drop_objection()
