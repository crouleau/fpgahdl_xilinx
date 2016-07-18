//Testbench for axi_ad9364_dig_if.v

`timescale 1ns/1ns

module axi_ad9364_data_gen
    (
        // physical interface (Rx - coming from the AD9364)
        rx_clk_in_phys_p, //TESTBENCH: For a testbench, comment me out!
        rx_clk_in_phys_n, //TESTBENCH: For a testbench, comment me out!
        rx_frame_in_phys_p,
        rx_frame_in_phys_n,
        rx_data_in_phys_p,
        rx_data_in_phys_n,

        // physical interface (Tx - going out to the AD9364)
        tx_clk_out_phys_p,
        tx_clk_out_phys_n,
        tx_frame_out_phys_p,,
        tx_frame_out_phys_n,
        tx_data_out_phys_p,
        tx_data_out_phys_n
    );

    // this parameter controls the buffer type based on the target device.
    parameter   PCORE_BUFTYPE = 1; //Using Virtex 6!
    localparam  PCORE_7SERIES = 0;
    localparam  PCORE_VIRTEX6 = 1;
    parameter ADC_RXTX_1_MODE = 1; //Set to 1 to use just 1 tx/rx channel (you can use 1rx2tx, etc, but not supported atm)

    // physical interface (Rx - input to module)
    reg           rx_clk_in_phys_p;
    reg           rx_clk_in_phys_n;
    input           rx_frame_in_phys_p;
    input           rx_frame_in_phys_n;
    input   [ 5:0]  rx_data_in_phys_p;
    input   [ 5:0]  rx_data_in_phys_n;

    // physical interface (Tx - receive from module)

    output          tx_clk_out_phys_p;
    output          tx_clk_out_phys_n;
    output          tx_frame_out_phys_p;
    output          tx_frame_out_phys_n;
    output  [ 5:0]  tx_data_out_phys_p;
    output  [ 5:0]  tx_data_out_phys_n;


    //*****Internal Signals begin now *****

    // clock (an output from the module - common to both receive and transmit)
    wire          clk;

    // receive data path interface
    wire          adc_valid;
    wire  [11:0]  adc_data_i1_rx;
    wire  [11:0]  adc_data_q1_rx;
    wire  [11:0]  adc_data_i2_rx;
    wire  [11:0]  adc_data_q2_rx;
    wire          adc_status;
    reg           adc_r1_mode;

    // transmit data path interface
    reg           dac_valid;
    reg [11:0]    dac_data_i1_gen;
    reg [11:0]    dac_data_q1_gen;
    reg [11:0]    dac_data_i2_gen;
    reg [11:0]    dac_data_q2_gen;
    reg           dac_r1_mode_gen;
    reg [1:0]     dac_data_sel;

    // chipscope signals
    wire  [ 3:0]  dev_dbg_trigger;
    wire [297:0]  dev_dbg_data;


    //tx - what the "HDL" we're plugged into is supposedly transmitting (alternating between 1 and 2)
    //This goes into the "dac_data" and we should result in data going out on "tx_data_out_phys"
    parameter idata1_tx = 12'o2064;
    parameter idata2_tx = 12'o4402;
    parameter qdata1_tx = 12'o1753;
    parameter qdata2_tx = 12'o1337;

    //TESTBENCH: For a testbench, uncomment this block!
    /*initial
        begin: CLK_GEN
        rx_clk_in_phys_p = 0;
        rx_clk_in_phys_n = 1;
    forever
        begin
            #100
            rx_clk_in_phys_p = ~rx_clk_in_phys_p;
            rx_clk_in_phys_n = ~rx_clk_in_phys_n;
        end
    end*/

    initial
        begin: DAC_DATA_GEN
        dac_valid = 1'b0;
        dac_data_i1_gen = 1'b0;
        dac_data_q1_gen = 1'b0;
        dac_data_i2_gen = 1'b0;
        dac_data_q2_gen = 1'b0;
        dac_data_sel = 2'b00;
        if(ADC_RXTX_1_MODE == 1) begin
            dac_r1_mode_gen = 1'b1;
            adc_r1_mode = 1'b1;
        end else begin
            dac_r1_mode_gen = 1'b0;
            adc_r1_mode = 1'b0;
        end

    forever
        begin
            @(posedge clk)
            if(ADC_RXTX_1_MODE == 1) begin
                case(dac_data_sel)
                    2'b00: begin
                        //On even clock edges, prep the data so that it can be read in
                        dac_data_sel <= dac_data_sel + 1'b1;
                        dac_valid <= 1'b1;
                        dac_data_i1_gen <= idata1_tx;
                        dac_data_q1_gen <= qdata1_tx;
                    end
                    2'b01: begin
                        //On odd clock edges, just set DAC valid false - the core is busy
                        //clocking out the previous data we gave it
                        dac_valid <= 1'b0;
                        dac_data_sel <= dac_data_sel + 1'b1;
                    end
                    2'b10: begin
                        //Now clock in the second set of alternating data
                        dac_data_sel <= dac_data_sel + 1'b1;
                        dac_valid <= 1'b1;
                        dac_data_i1_gen <= idata2_tx;
                        dac_data_q1_gen <= qdata2_tx;
                    end
                    2'b11: begin
                        dac_valid <= 1'b0;
                        dac_data_sel <= dac_data_sel + 1'b1;
                    end
                    default: begin
                        dac_data_sel <= 2'b00; //Shouldn't get here, but just for safety I suppose
                    end
                endcase
            end else begin
                dac_valid <= 1'b0;
                dac_data_i1_gen <= 0'o0000;
                dac_data_q1_gen <= 0'o0000; //not implemented
            end
        end
    end

    axi_ad9364_dig_if #(
        .PCORE_BUFTYPE (PCORE_BUFTYPE))
    i_dev_if (
        .rx_clk_in_p (rx_clk_in_phys_p),
        .rx_clk_in_n (rx_clk_in_phys_n),
        .rx_frame_in_p (rx_frame_in_phys_p),
        .rx_frame_in_n (rx_frame_in_phys_n),
        .rx_data_in_p (rx_data_in_phys_p),
        .rx_data_in_n (rx_data_in_phys_n),
        .tx_clk_out_p (tx_clk_out_phys_p),
        .tx_clk_out_n (tx_clk_out_phys_n),
        .tx_frame_out_p (tx_frame_out_phys_p),
        .tx_frame_out_n (tx_frame_out_phys_n),
        .tx_data_out_p (tx_data_out_phys_p),
        .tx_data_out_n (tx_data_out_phys_n),
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

endmodule