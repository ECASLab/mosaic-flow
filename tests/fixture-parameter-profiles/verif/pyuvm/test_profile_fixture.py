"""PyUVM qualification for every parameterized fixture elaboration."""

from __future__ import annotations

import json
import os

import cocotb
from cocotb.triggers import Timer
from pyuvm import test, uvm_test


@test()
class ProfileFixtureTest(uvm_test):
    """Check width and feature behavior using the selected profile evidence."""

    async def run_phase(self) -> None:
        """Drive all ones and check the selected feature implementation."""
        self.raise_objection()
        parameters = json.loads(os.environ["PROFILE_PARAMETERS_JSON"])
        width = int(parameters["WIDTH"])
        invert = bool(parameters["FEATURE_INVERT"])
        mask = (1 << width) - 1
        cocotb.top.data_i.value = mask
        await Timer(1, unit="ns")
        expected = 0 if invert else mask
        assert int(cocotb.top.data_o.value) == expected
        self.drop_objection()
