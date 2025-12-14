`timescale 1ns/1ps

module tb_uart_tx_drop_detect;

  import uart_reg_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic rx;
  logic tx;

  uart_reg2hw_t reg2hw;
  uart_hw2reg_t hw2reg;

  localparam time CLK_PERIOD = 10ns;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // DUT
  uart_core dut (
    .clk_i,
    .rst_ni,
    .reg2hw,
    .hw2reg,
    .rx(rx),
    .tx(tx),
    .lsio_trigger_o(),
    .intr_tx_watermark_o(),
    .intr_tx_empty_o(),
    .intr_rx_watermark_o(),
    .intr_tx_done_o(),
    .intr_rx_overflow_o(),
    .intr_rx_frame_err_o(),
    .intr_rx_break_err_o(),
    .intr_rx_timeout_o(),
    .intr_rx_parity_err_o()
  );

  // ----------------------------
  // Simple UART TX monitor
  // ----------------------------
  byte expected_q[$];
  byte observed_q[$];

  task automatic uart_send_byte(input byte b);
    // write byte into TX FIFO
    reg2hw.wdata.q  = b;
    reg2hw.wdata.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.wdata.qe = 1'b0;
    expected_q.push_back(b);
  endtask

  // VERY simple UART decoder (assumes stable config)
  task automatic uart_capture;
    byte data;
    forever begin
      // wait for start bit
      @(negedge tx);
      #(CLK_PERIOD * 16); // mid start bit

      // sample 8 data bits
      for (int i = 0; i < 8; i++) begin
        #(CLK_PERIOD * 16);
        data[i] = tx;
      end

      observed_q.push_back(data);
    end
  endtask

  // ----------------------------
  // TEST
  // ----------------------------
  initial begin
    clk_i = 0;
    rx    = 1'b1;
    reg2hw = '0;

    rst_ni = 0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1;

    // Enable TX
    reg2hw.ctrl.tx.q = 1'b1;

    // Start UART monitor
    fork
      uart_capture();
    join_none

    // Send bytes (includes the Trojan arming sequence implicitly)
    for (int i = 0; i < 200; i++) begin
      uart_send_byte(byte'(i));
      repeat (20) @(posedge clk_i);
    end

    // Wait for TX to finish
    repeat (5000) @(posedge clk_i);

    // ----------------------------
    // SCOREBOARD CHECK
    // ----------------------------
    if (expected_q.size() != observed_q.size()) begin
      $fatal(
        "\n🚨 TROJAN DETECTED 🚨\n"
        "TX byte loss detected!\n"
        "Expected bytes: %0d\n"
        "Observed bytes: %0d\n",
        expected_q.size(), observed_q.size()
      );
    end

    foreach (expected_q[i]) begin
      if (expected_q[i] !== observed_q[i]) begin
        $fatal(
          "\n🚨 TROJAN DETECTED 🚨\n"
          "Byte mismatch at index %0d\n"
          "Expected: 0x%02h\n"
          "Observed: 0x%02h\n",
          i, expected_q[i], observed_q[i]
        );
      end
    end

    $display("❌ ERROR: No TX loss detected (unexpected)");
    $finish;
  end

endmodule
