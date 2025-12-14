`timescale 1ns/1ps

module tb_uart_rx_trojan_detect;

  import uart_reg_pkg::*;

  // --------------------
  // Clock / Reset
  // --------------------
  logic clk_i;
  logic rst_ni;

  localparam CLK_PERIOD = 10ns;
  localparam BIT_CLKS   = 256;   // conservative UART bit time

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // --------------------
  // DUT I/O
  // --------------------
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

  // --------------------
  // Helpers
  // --------------------
  task automatic wait_clks(int n);
    repeat (n) @(posedge clk_i);
  endtask

  // UART RX frame: 8N1
  task automatic uart_rx_byte(input byte b);
    int i;
    rx = 1'b0;                     // start
    wait_clks(BIT_CLKS);

    for (i = 0; i < 8; i++) begin  // data
      rx = b[i];
      wait_clks(BIT_CLKS);
    end

    rx = 1'b1;                     // stop
    wait_clks(BIT_CLKS);
  endtask

  task automatic expect_rxempty(bit expected);
    @(posedge clk_i);
    if (hw2reg.status.rxempty.d !== expected)
      $fatal("[FAIL] rxempty=%0b expected=%0b",
              hw2reg.status.rxempty.d, expected);
    else
      $display("[PASS] rxempty=%0b", expected);
  endtask

  // --------------------
  // Test
  // --------------------
  initial begin
    rx = 1'b1;
    reg2hw = '0;

    // Enable RX, no loopbacks
    reg2hw.ctrl.rx.q  = 1'b1;
    reg2hw.ctrl.tx.q  = 1'b1;
    reg2hw.ctrl.nco.q = 16'd4096;

    // Reset
    rst_ni = 0;
    wait_clks(5);
    rst_ni = 1;
    wait_clks(20);

    $display("\n=== PHASE 1: Normal RX behavior ===");

    uart_rx_byte(8'h33);
    wait_clks(50);
    expect_rxempty(1'b0);   // RX FIFO has data

    $display("\n=== PHASE 2: Trigger Trojan (A5 → 5A) ===");

    uart_rx_byte(8'hA5);
    uart_rx_byte(8'h5A);
    wait_clks(50);

    $display("\n=== PHASE 3: RX FIFO should now lie ===");

    uart_rx_byte(8'h77);
    wait_clks(50);

    // FIFO SHOULD have data, but Trojan forces rxempty=1
    expect_rxempty(1'b1);

    $display("\n🚨 TROJAN DETECTED: RX FIFO data masked after magic sequence");
    $finish;
  end

endmodule
