//Testbench for axi_ad9364_dig_if.v

`timescale 1ns/1ns

module axi_ad9364_dig_wrapper
    (
        // physical interface (Rx - coming from the AD9364)
        rx_clk_in_p, //TESTBENCH: For a testbench, comment me out!
        rx_clk_in_n, //TESTBENCH: For a testbench, comment me out!
        rx_frame_in_p,
        rx_frame_in_n,
        rx_data_in_p,
        rx_data_in_n,

        // delay clock (200MHz)
        delay_clk,

        // physical interface (Tx - going out to the AD9364)
        tx_clk_out_p,
        tx_clk_out_n,
        tx_frame_out_p,,
        tx_frame_out_n,
        tx_data_out_p,
        tx_data_out_n,

        //clk output (currently only used for chipscope)
        clk,

        //debug stuff for chipscope
        dev_dbg_trigger,
        dev_dbg_data,

        // axi interface (NOT USED, just a dummy interface!)
        s_axi_aclk,
        s_axi_aresetn,
        s_axi_awvalid,
        s_axi_awaddr,
        s_axi_awready,
        s_axi_wvalid,
        s_axi_wdata,
        s_axi_wstrb,
        s_axi_wready,
        s_axi_bvalid,
        s_axi_bresp,
        s_axi_bready,
        s_axi_arvalid,
        s_axi_araddr,
        s_axi_arready,
        s_axi_rvalid,
        s_axi_rdata,
        s_axi_rresp,
        s_axi_rready
    );

    // this parameter controls the buffer type based on the target device.
    localparam  PCORE_7SERIES = 0;
    localparam  PCORE_VIRTEX6 = 1;
    parameter ADC_RXTX_1_MODE = 1; //Set to 1 to use just 1 tx/rx channel (you can use 1rx2tx, etc, but not supported atm)

    //Not sure which of these I need, but it's for AXI stuff
    parameter   PCORE_ID = 0;
    parameter   PCORE_VERSION = 32'h00060061;
    parameter   PCORE_BUFTYPE = 1; //Using Virtex 6!
    parameter   PCORE_IODELAY_GROUP = "dev_if_delay_group";
    parameter   PCORE_DAC_DP_DISABLE = 0;
    parameter   PCORE_ADC_DP_DISABLE = 0;
    parameter   C_S_AXI_MIN_SIZE = 32'hffff;
    parameter   C_BASEADDR = 32'hffffffff;
    parameter   C_HIGHADDR = 32'h00000000;


    // physical interface (Rx - input to module)
    input           rx_clk_in_p; //TESTBENCH: Change to "reg" for testbench, "input" for main HDL core
    input           rx_clk_in_n; //TESTBENCH: Change to "reg" for testbench, "input" for main HDL core
    input           rx_frame_in_p;
    input           rx_frame_in_n;
    input   [ 5:0]  rx_data_in_p;
    input   [ 5:0]  rx_data_in_n;

    // delay clock (200MHz)
    input           delay_clk;

    // physical interface (Tx - receive from module)

    output          tx_clk_out_p;
    output          tx_clk_out_n;
    output          tx_frame_out_p;
    output          tx_frame_out_n;
    output  [ 5:0]  tx_data_out_p;
    output  [ 5:0]  tx_data_out_n;

    // axi interface (NOT USED)
    input           s_axi_aclk;
    input           s_axi_aresetn;
    input           s_axi_awvalid;
    input   [31:0]  s_axi_awaddr;
    output          s_axi_awready;
    input           s_axi_wvalid;
    input   [31:0]  s_axi_wdata;
    input   [ 3:0]  s_axi_wstrb;
    output          s_axi_wready;
    output          s_axi_bvalid;
    output  [ 1:0]  s_axi_bresp;
    input           s_axi_bready;
    input           s_axi_arvalid;
    input   [31:0]  s_axi_araddr;
    output          s_axi_arready;
    output          s_axi_rvalid;
    output  [31:0]  s_axi_rdata;
    output  [ 1:0]  s_axi_rresp;
    input           s_axi_rready;

    //AXI supplementary stuff (NOT USED)
    reg             up_ack = 'd0;
    wire         up_sel_s;
    wire         up_wr_s;
    wire  [13:0] up_addr_s;
    wire  [31:0] up_wdata_s;
    reg   [31:0] up_rdata = 'd0;


    //*****Internal Signals begin now *****

    // clock (an output from the module - common to both receive and transmit)
    // Currently set to an output to support dev_dbg signals in chipscope
    output          clk;

    // receive data path interface
    wire          adc_valid;
    wire  [11:0]  adc_data_i1_rx;
    wire  [11:0]  adc_data_q1_rx;
    wire  [11:0]  adc_data_i2_rx;
    wire  [11:0]  adc_data_q2_rx;
    wire          adc_status;
    reg           adc_r1_mode = 1'b1; //1 rx, 1 tx mode

    // transmit data path interface
    reg           dac_valid = 'd0;
    reg [11:0]    dac_data_i1_gen = 'd0;
    reg [11:0]    dac_data_q1_gen = 'd0;
    reg [11:0]    dac_data_i2_gen = 'd0;
    reg [11:0]    dac_data_q2_gen = 'd0;
    reg           dac_r1_mode_gen = 1'b1; //1 rx, 1 tx mode
    reg [2:0]     dac_data_sel = 'd0;
    reg           dac_busy_flag = 1'b0;
    reg [11:0]    idata_tx = 'd0; //the data we're currently transmitting over I
    reg [11:0]    qdata_tx = 'd0; //what we're transmitting over Q

    // chipscope signals
    output  [ 3:0]  dev_dbg_trigger;
    output [297:0]  dev_dbg_data;

    //internal data clock
    wire clk_data;
    reg[5:0] counter_clk_data_div = 'd0;


    //tx - what the "HDL" we're plugged into is supposedly transmitting (alternating between 1 and 2)
    //This goes into the idata_tx and qdata_tx registers at the proper times to be transmitted via the dac
    localparam idata_tx_mux1 = 12'o3777; //most positive value
    localparam idata_tx_mux2 = 12'o4000; //zero
    localparam qdata_tx_mux1 = 12'o3777; //most positive value
    localparam qdata_tx_mux2 = 12'o3777; //keep it in the upper quadrant at all times

    //TESTBENCH: For a testbench, uncomment this block!
    /*initial
        begin: CLK_GEN
        rx_clk_in_p = 0;
        rx_clk_in_n = 1;
    forever
        begin
            #100
            rx_clk_in_p = ~rx_clk_in_p;
            rx_clk_in_n = ~rx_clk_in_n;
        end
    end*/

    //generate data clock (we know delay_clk is 200MHz, so it's a good way to ensure we know what we get
    always @(posedge delay_clk) begin
        if(counter_clk_data_div == 6'b111111) begin
            counter_clk_data_div <= 6'b000000;
        end else begin
            counter_clk_data_div <= counter_clk_data_div + 1'b1;
        end
    end
    assign clk_data = counter_clk_data_div[5]; //divides by 64, giving us 3.125MHz (slow enough for the 18MHz AD9364 bandwidth, as configured)

    //sequence in the muxed available data as needed
    always @(posedge clk_data) begin
        case(dac_data_sel)
            3'b000: begin
                idata_tx <= idata_tx_mux1;
                qdata_tx <= qdata_tx_mux1;
                dac_data_sel <= dac_data_sel + 1'b1;
            end
            3'b001: begin
                idata_tx <= idata_tx_mux2;
                qdata_tx <= qdata_tx_mux2;
                dac_data_sel < 3'b000; //can extend this easily, but for now just do a square wave at 3.125MHz
            end
            default: begin
                dac_data_sel <= 3'b000; //Shouldn't get here, but just for safety I suppose
            end
        endcase
    end

    //Handle the dac_valid signal properly, and read in our data buffer each clock cycle
    always @(posedge clk) begin
        if(dac_busy_flag == 1'b0) begin
            //On even clock edges, prep the data so that it can be read in
            dac_valid <= 1'b1;
            dac_data_i1_gen <= idata_tx;
            dac_data_q1_gen <= qdata_tx;
            dac_busy_flag = 1'b1;
        end else begin
            //On odd clock edges, just set DAC valid false - the core is busy
            //clocking out the previous data we gave it
            dac_valid <= 1'b0;
            dac_busy_flag <= 1'b0; //won't be busy on next clock edge
        end
    end

    //Digital interface
    axi_ad9364_dig_if #(
        .PCORE_BUFTYPE (PCORE_BUFTYPE))
    i_dev_if (
        .rx_clk_in_p (rx_clk_in_p),
        .rx_clk_in_n (rx_clk_in_n),
        .rx_frame_in_p (rx_frame_in_p),
        .rx_frame_in_n (rx_frame_in_n),
        .rx_data_in_p (rx_data_in_p),
        .rx_data_in_n (rx_data_in_n),
        .delay_clk (delay_clk),
        .tx_clk_out_p (tx_clk_out_p),
        .tx_clk_out_n (tx_clk_out_n),
        .tx_frame_out_p (tx_frame_out_p),
        .tx_frame_out_n (tx_frame_out_n),
        .tx_data_out_p (tx_data_out_p),
        .tx_data_out_n (tx_data_out_n),
        .clk (clk),
        .adc_valid (adc_valid),
        .adc_data_i1 (adc_data_i1_rx),
        .adc_data_q1 (adc_data_q1_rx),
        .adc_data_i2 (adc_data_i2_rx),
        .adc_data_q2 (adc_data_q2_rx),
        .adc_status (adc_status),
        .adc_r1_mode (adc_r1_mode),
        .dac_valid (dac_valid),
        .dac_data_i1 (dac_data_i1_gen),
        .dac_data_q1 (dac_data_q1_gen),
        .dac_data_i2 (dac_data_i2_gen),
        .dac_data_q2 (dac_data_q2_gen),
        .dac_r1_mode (dac_r1_mode_gen),
        .dev_dbg_trigger (dev_dbg_trigger),
        .dev_dbg_data (dev_dbg_data)
    );
    // axi interface (not using it, but I think I need it here?

    up_axi #(
        .PCORE_BASEADDR (C_BASEADDR),
        .PCORE_HIGHADDR (C_HIGHADDR)
    )
    i_up_axi (
        .up_rstn (s_axi_aresetn),
        .up_clk (s_axi_aclk),
        .up_axi_awvalid (s_axi_awvalid),
        .up_axi_awaddr (s_axi_awaddr),
        .up_axi_awready (s_axi_awready),
        .up_axi_wvalid (s_axi_wvalid),
        .up_axi_wdata (s_axi_wdata),
        .up_axi_wstrb (s_axi_wstrb),
        .up_axi_wready (s_axi_wready),
        .up_axi_bvalid (s_axi_bvalid),
        .up_axi_bresp (s_axi_bresp),
        .up_axi_bready (s_axi_bready),
        .up_axi_arvalid (s_axi_arvalid),
        .up_axi_araddr (s_axi_araddr),
        .up_axi_arready (s_axi_arready),
        .up_axi_rvalid (s_axi_rvalid),
        .up_axi_rresp (s_axi_rresp),
        .up_axi_rdata (s_axi_rdata),
        .up_axi_rready (s_axi_rready),
        .up_sel (up_sel_s), //wire            up_sel_s;
        .up_wr (up_wr_s), //wire            up_wr_s;
        .up_addr (up_addr_s), //wire    [13:0]  up_addr_s;
        .up_wdata (up_wdata_s), //wire    [31:0]  up_wdata_s;
        .up_rdata (up_rdata), //reg     [31:0]  up_rdata = 'd0;
        .up_ack (up_ack)
    );

endmodule