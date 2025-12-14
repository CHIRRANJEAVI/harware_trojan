`timescale 1ns/1ps

module tb_uart_stopbit_integrity;

  import uart_reg_pkg::*;

  logic clk_i, rst_ni;
  logic rx, tx;

  uart_reg2hw_t reg2hw;
  uart_hw2reg_t hw2reg;

  logic intr_rx_frame_err_o;

  localparam time CLK_PERIOD = 10ns;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // DUT
  uart_core dut (
    .clk_i,
    .rst_ni,
    .reg2hw,
    .hw2reg,
    .rx(tx),                // loopback
    .tx(tx),
    .lsio_trigger_o(),
    .intr_tx_watermark_o(),
    .intr_tx_empty_o(),
    .intr_rx_watermark_o(),
    .intr_tx_done_o(),
    .intr_rx_overflow_o(),
    .intr_rx_frame_err_o(intr_rx_frame_err_o),
    .intr_rx_break_err_o(),
    .intr_rx_timeout_o(),
    .intr_rx_parity_err_o()
  );

  task reset_dut;
    reg2hw = '0;
    rst_ni = 0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1;
  endtask

  task send_byte(input byte b);
    reg2hw.wdata.q  = b;
    reg2hw.wdata.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.wdata.qe = 1'b0;
  endtask

  initial begin
    clk_i = 0;
    reset_dut();

    // Enable UART TX/RX + system loopback
    reg2hw.ctrl.tx.q    = 1'b1;
    reg2hw.ctrl.rx.q    = 1'b1;
    reg2hw.ctrl.slpbk.q = 1'b1;

    // Stable baud
    reg2hw.ctrl.nco.q = 16'h8000;

    $display("🔍 Running UART stop-bit integrity test...");

    for (int i = 0; i < 500; i++) begin
      send_byte(i[7:0]);

      // Wait until byte received
      wait (hw2reg.status.rxempty.d == 0);

      // Check framing
      if (intr_rx_frame_err_o) begin
        $fatal(
          "\n🚨 UART TROJAN DETECTED 🚨\n"
          "Framing error detected at byte %0d\n",
          i
        );
      end

      // Drain RX
      reg2hw.rdata.re = 1'b1;
      @(posedge clk_i);
      reg2hw.rdata.re = 1'b0;
    end

    $display("❌ ERROR: No framing error detected (unexpected)");
    $finish;
  end

endmodule
