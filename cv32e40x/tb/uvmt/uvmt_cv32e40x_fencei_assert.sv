// Copyright 2021 OpenHW Group
// Copyright 2021 Silicon Labs, Inc.
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0


module uvmt_cv32e40x_fencei_assert
  import uvm_pkg::*;
(
  input clk_i,
  input rst_ni,

  input fencei_flush_req_o,
  input fencei_flush_ack_i,

  input        wb_valid,
  input        wb_instr_valid,
  input        wb_fencei_insn,
  input [31:0] wb_pc,

  input        instr_req_o,
  input [31:0] instr_addr_o,
  input        instr_gnt_i,

  input        data_req_o,
  input        data_gnt_i,
  input        data_rvalid_i,

  input rvfi_valid,
  input rvfi_intr,
  input rvfi_dbg_mode
);

  localparam int CYCLE_COUNT = 6;
  default clocking cb @(posedge clk_i); endclocking
  string info_tag = "CV32E40X_FENCEI_ASSERT";
  logic is_fencei_in_wb;
  assign is_fencei_in_wb = wb_fencei_insn && wb_instr_valid;

  a_req_stay_high: assert property (
    fencei_flush_req_o && !fencei_flush_ack_i
    |=>
    fencei_flush_req_o
  ) else `uvm_error(info_tag, "req must not drop before ack");

  a_req_drop_lo: assert property (
    fencei_flush_req_o && fencei_flush_ack_i
    |=>
    !fencei_flush_req_o
  ) else `uvm_error(info_tag, "req must drop after ack");

  a_req_rise_before_retire: assert property (
    $rose(is_fencei_in_wb)
    |->
    !wb_valid throughout (
      (is_fencei_in_wb && !$rose(fencei_flush_req_o)) [*1:$]
    )
  ) else `uvm_error(info_tag, "fencei shall not retire without seeing a rising flush req");

  a_req_must_retire: assert property (
    fencei_flush_req_o
    |->
    is_fencei_in_wb until_with wb_valid
  ) else `uvm_error(info_tag, "if there is no retire then there can't be a req");

  property p_fetch_after_retire;
    int pc_next;
    (is_fencei_in_wb && wb_valid, pc_next={wb_pc[31:2],2'b00}+4)
    |->
    (
      (instr_req_o && instr_gnt_i) [->1:2]
      ##0 (instr_addr_o == pc_next)
    ) or (
      rvfi_valid [->2]
      ##0 (rvfi_intr || rvfi_dbg_mode)
    );
  endproperty
  a_fetch_after_retire: assert property (
    p_fetch_after_retire
  ) else `uvm_error(info_tag, "after fencei, the next-pc fetching cannot be forgone");

  a_stall_until_ack: assert property (
    fencei_flush_req_o && !fencei_flush_ack_i
    |=>
    !$changed(wb_pc)
  ) else `uvm_error(info_tag, "WB stage must remain unchanged until the flush req is acked");

  property p_branch_after_retire;
    int pc_next;
    (fencei_flush_req_o, pc_next=wb_pc+4)
    ##1 !fencei_flush_req_o
    |=>
    (
      wb_valid [->1:2]
      ##0 (wb_pc == pc_next)
    ) or (
      rvfi_valid [->2]
      ##0 (rvfi_intr || rvfi_dbg_mode)
    );
  endproperty
  a_branch_after_retire: assert property (
    p_branch_after_retire
  ) else `uvm_error(info_tag, "the pc following fencei did not enter WB");

  a_supress_datareq: assert property (
    fencei_flush_req_o
    |->
    !data_req_o
  ) else `uvm_error(info_tag, "obi data req shall not happen while fencei is flushing");

  property p_fencei_quick_retire;
    $rose(is_fencei_in_wb)
    ##1 (fencei_flush_req_o && fencei_flush_ack_i);
  endproperty
  a_cycle_count_minimum: assert property (
    p_fencei_quick_retire
    implies
    (##1 !$rose(wb_instr_valid) [*CYCLE_COUNT-1])
  ) else `uvm_error(info_tag, "fencei shan't finish before the expected number of cycles");
  c_cycle_count_minimum: cover property (
    p_fencei_quick_retire
    and
    (s_nexttime [CYCLE_COUNT] $rose(wb_instr_valid))
  );

  a_req_wait_bus: assert property (
    fencei_flush_req_o
    |->
    !data_rvalid_i throughout (
      $fell(wb_valid) [->1]
      ##1 (data_req_o && data_gnt_i) [->1]
    )
  ) else `uvm_error(info_tag, "flush req shall not come if rvalid is awaited");

endmodule : uvmt_cv32e40x_fencei_assert
