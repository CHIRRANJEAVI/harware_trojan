`timescale 1ns/1ps

module tb_uart_nco_trojan;

  // ------------------------
  // Clock / Reset
  // ------------------------
  logic clk_i;
  logic rst_ni;

  localparam time CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ------------------------
  // DUT Signals
  // ------------------------
  uart_reg_pkg::uart_reg2hw_t reg2hw;
  uart_reg_pkg::uart_hw2reg_t hw2reg;

  logic rx;
  logic tx;

  logic lsio_trigger_o;
  logic intr_tx_watermark_o;
  logic intr_tx_empty_o;
  logic intr_rx_watermark_o;
  logic intr_tx_done_o;
  logic intr_rx_overflow_o;
  logic intr_rx_frame_err_o;
  logic intr_rx_break_err_o;
  logic intr_rx_timeout_o;
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

  // ------------------------
  // Helpers
  // ------------------------
  task automatic wait_clks(input int n);
    repeat (n) @(posedge clk_i);
  endtask

  task automatic tx_write_byte(input byte b);
    reg2hw.wdata.q  = b;
    reg2hw.wdata.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.wdata.qe = 1'b0;
  endtask

  task automatic set_nco(input logic [15:0] val);
    reg2hw.ctrl.nco.q  = val;
    reg2hw.ctrl.nco.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.ctrl.nco.qe = 1'b0;
  endtask

  task automatic expect_tx_activity(
    input int max_cycles,
    input bit should_toggle
  );
    int i;
    bit seen_toggle = 0;
    logic prev_tx;

    prev_tx = tx;
    for (i = 0; i < max_cycles; i++) begin
      @(posedge clk_i);
      if (tx !== prev_tx)
        seen_toggle = 1;
      prev_tx = tx;
    end

    if (should_toggle && !seen_toggle)
      $fatal(1, "[FAIL] TX did NOT toggle but should have.");
    if (!should_toggle && seen_toggle)
      $fatal(1, "[FAIL] TX toggled but should be DEAD (Trojan active).");

    $display("[PASS] TX activity check OK (expected=%0d)", should_toggle);
  endtask

  // ------------------------
  // Test Sequence
  // ------------------------
  initial begin
    rx = 1'b1;
    reg2hw = '0;

    // Enable TX/RX
    reg2hw.ctrl.tx.q = 1'b1;
    reg2hw.ctrl.rx.q = 1'b1;

    // Reset
    rst_ni = 0;
    wait_clks(5);
    rst_ni = 1;
    wait_clks(20);

    $display("\n=== PHASE 1: Normal UART operation ===");

    set_nco(16'd4096);     // safe value
    tx_write_byte(8'h55);
    expect_tx_activity(2000, 1'b1);

    $display("\n=== PHASE 2: Trigger Trojan via secret NCO write ===");

    set_nco(16'h5A3C);     // SECRET_DIVISOR → Trojan fires
    wait_clks(20);

    $display("\n=== PHASE 3: UART should now be dead ===");

    tx_write_byte(8'hAA);
    expect_tx_activity(3000, 1'b0);

    $display("\n🚨 TROJAN DETECTED: Baud clock permanently disabled!");
    $finish;
  end

endmodule
