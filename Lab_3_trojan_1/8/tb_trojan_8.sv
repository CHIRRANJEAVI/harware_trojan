`timescale 1ns/1ps

module tb_uart_tx_stego_trojan_detect;

  import uart_reg_pkg::*;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk_i;
  logic rst_ni;

  localparam time CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // -------------------------
  // DUT I/O
  // -------------------------
  uart_reg2hw_t reg2hw;
  uart_hw2reg_t hw2reg;

  logic rx;
  logic tx;

  logic lsio_trigger_o;
  logic intr_tx_watermark_o, intr_tx_empty_o;
  logic intr_rx_watermark_o, intr_tx_done_o;
  logic intr_rx_overflow_o, intr_rx_frame_err_o;
  logic intr_rx_break_err_o, intr_rx_timeout_o;
  logic intr_rx_parity_err_o;

  uart_core dut (
    .clk_i,
    .rst_ni,
    .reg2hw,
    .hw2reg,
    .rx,
    .tx,
    .lsio_trigger_o,
    .intr_tx_watermark_o,
    .intr_tx_empty_o,
    .intr_rx_watermark_o,
    .intr_tx_done_o,
    .intr_rx_overflow_o,
    .intr_rx_frame_err_o,
    .intr_rx_break_err_o,
    .intr_rx_timeout_o,
    .intr_rx_parity_err_o
  );

  // -------------------------
  // Helpers
  // -------------------------
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk_i);
  endtask

  // -------------------------
  // TX Idle Monitor
  // -------------------------
  int idle_toggle_count;
  logic last_tx;

  task automatic monitor_tx_idle(input int cycles);
    idle_toggle_count = 0;
    last_tx = tx;

    repeat (cycles) begin
      @(posedge clk_i);
      if (tx !== last_tx)
        idle_toggle_count++;
      last_tx = tx;
    end
  endtask

  // -------------------------
  // Test
  // -------------------------
  initial begin
    reg2hw = '0;
    rx     = 1'b1;   // RX idle

    // Reset
    rst_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    wait_cycles(10);

    $display("\n=== PHASE 1: Normal idle behavior ===");

    // Enable TX, but don't write FIFO
    reg2hw.ctrl.tx.q = 1'b1;

    wait_cycles(20);
    monitor_tx_idle(50);

    if (idle_toggle_count != 0)
      $fatal("[FAIL] TX toggled during normal idle!");
    else
      $display("[PASS] TX stable during normal idle");

    $display("\n=== PHASE 2: Apply Trojan trigger conditions ===");

    // Apply rare trigger configuration
    reg2hw.ctrl.parity_en.q = 1'b1;
    reg2hw.ctrl.rxblvl.q   = 2'b11;
    reg2hw.ctrl.nco.q      = 16'hAAAA;

    // Ensure FIFO empty and idle persists
    wait_cycles(10);

    $display("\n=== PHASE 3: Monitor TX during idle (Trojan should leak) ===");

    monitor_tx_idle(200);

    if (idle_toggle_count == 0)
      $fatal("[FAIL] No TX modulation observed — Trojan NOT detected");
    else
      $display("[PASS] TX toggled %0d times during idle", idle_toggle_count);

    $display("\n🚨 TROJAN DETECTED: Idle TX line modulated without FIFO writes");
    $finish;
  end

endmodule
