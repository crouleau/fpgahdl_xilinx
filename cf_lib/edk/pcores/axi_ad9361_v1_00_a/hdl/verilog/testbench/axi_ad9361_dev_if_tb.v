//Testbench for axi_ad9361_dev_if.v

`timescale 1ns/1ns

module axi_ad9361_dev_if_tb
    (
        //No physical interface
        //Use "-novopt" in modelsim to ensure signal visibility
    );

    // this parameter controls the buffer type based on the target device.
    parameter   PCORE_BUFTYPE = 1; //Using Virtex 6!
    localparam  PCORE_7SERIES = 0;
    localparam  PCORE_VIRTEX6 = 1;

    //simulation params
    parameter ADC_RXTX_1_MODE = 1; //Set to 1 to use just 1 tx/rx channel (you can use 1rx2tx, etc, but not supported atm)

    // physical interface (Rx - input to module)

    //Data clock - maxes out at 247.76MHz for LVDS, seems to be set automatically.
    //  See "DATA_CLK" in documentation
    // Note that we are using LVDS mode by default in the driver
    // DATA_CLK = 2 x RX_SAMPL_FREQ (see code) for the AD9364 using LVDS (there are options if using the AD9361)
    //RX_SAMPL_FREQ is set by a divider relating to whether there's an FIR thing going on, and divided by a bunch of clks
    // see ad9361_calculate_rf_clock_chain
    reg           rx_clk_in_p_tb; //simulate DATA_CLK_P in fmcomms4
    reg           rx_clk_in_n_tb; //Need to simulate DATA_CLK_N in fmcomms4
    reg           rx_frame_in_p_tb; //This comes from the AD9364 ("RX_FRAME_P")
    reg           rx_frame_in_n_tb;
    reg   [ 5:0]  rx_data_in_p_tb;
    reg   [ 5:0]  rx_data_in_n_tb;

    // physical interface (Tx - receive from module)

    //tx_clk_out_p/n goes to FB_CLK_P/N
    wire          tx_clk_out_p_tb;
    wire          tx_clk_out_n_tb;
    wire          tx_frame_out_p_tb;
    wire          tx_frame_out_n_tb;
    wire  [ 5:0]  tx_data_out_p_tb;
    wire  [ 5:0]  tx_data_out_n_tb;

    // clock (an output from the module - common to both receive and transmit)
    wire          clk_tb;

    // receive data path interface

    wire          adc_valid_tb;
    wire  [11:0]  adc_data_i1_tb;
    wire  [11:0]  adc_data_q1_tb;
    wire  [11:0]  adc_data_i2_tb;
    wire  [11:0]  adc_data_q2_tb;
    wire          adc_status_tb;
    reg           adc_r1_mode_tb;

    // transmit data path interface

    reg           dac_valid_tb;
    reg   [11:0]  dac_data_i1_tb;
    reg   [11:0]  dac_data_q1_tb;
    reg   [11:0]  dac_data_i2_tb;
    reg   [11:0]  dac_data_q2_tb;
    reg           dac_r1_mode_tb;

    // chipscope signals
    wire  [ 3:0]  dev_dbg_trigger_tb;
    wire [297:0]  dev_dbg_data_tb;

    //Not sure how you're supposed to do this, but this seems to work...
    //assign rx_clk_in_p_tb_o = rx_clk_in_p_tb;

    initial
        begin: CLK_GEN
        rx_clk_in_p_tb = 0;
        rx_clk_in_n_tb = 1;
    forever
        begin
            #100
            rx_clk_in_p_tb = ~rx_clk_in_p_tb;
            rx_clk_in_n_tb = ~rx_clk_in_n_tb;
        end
    end

    initial
        begin: RX_FRAME_GEN
        rx_frame_in_p_tb = 0;
        rx_frame_in_n_tb = 1;
    forever
        begin
            //in 1rx 1tx mode, switch the frame at every positive clock edge
            //See page 110 of the AD9361 Reference Manual (rx_clk_in_p is hooked up to DATA_CLK_P)
            if(ADC_RXTX_1_MODE == 1) begin
                @(posedge rx_clk_in_p_tb)
                #1;
                rx_frame_in_p_tb = ~rx_frame_in_p_tb;
                rx_frame_in_n_tb = ~rx_frame_in_n_tb;
            //in 2rx 2tx mode, switch the frame every other positive clock edge
            end else begin
                @(posedge rx_clk_in_p_tb)
                #1
                @(posedge rx_clk_in_p_tb)
                #1
                rx_frame_in_p_tb = ~rx_frame_in_p_tb;
                rx_frame_in_n_tb = ~rx_frame_in_n_tb;
            end
        end
    end

    //wire up dac_r1_mode and adc_r1_mode based on the param value
    always @(*) begin
        if(ADC_RXTX_1_MODE == 1) begin
            dac_r1_mode_tb = 1'b1;
            adc_r1_mode_tb = 1'b1;
        end else begin
            dac_r1_mode_tb = 1'b0;
            adc_r1_mode_tb = 1'b0;
        end
    end


    //Insert data generation here... for now making it static (still have to clock it because of high/low bit transitions)
    initial
        begin: RX_DATA_GEN
            rx_data_in_p_tb = 6'b000000;
    forever
        begin
            //in 1rx 1tx mode, the high bits go at the positive edge of the frame (I then Q)
            //and low bits do the same at the negative edge of the frame
            if(ADC_RXTX_1_MODE == 1) begin
                @(posedge rx_frame_in_p_tb)
                #1
                rx_data_in_p_tb = 6'b101010; //I data, 11:6
                //Now wait for the negative edge of the clock to put in the Q data
                @(negedge rx_clk_in_p_tb)
                #1
                rx_data_in_p_tb = 6'b001001; //Q data, 11:6

                @(negedge rx_frame_in_p_tb) //Not sure if making this sequential is "proper"
                #1
                rx_data_in_p_tb = 6'b110110; //I data, 5:0

                @(negedge rx_clk_in_p_tb)
                #1
                rx_data_in_p_tb = 6'b100010; //Q data, 5:0
            //In 2rx 2tx mode, you do all the 11:6, I then Q, then 5:0, I then Q, for channel 1 on the pos edge of the frame
            //and the same for channel 2 but on the negative edge of the frame
            end else begin
                rx_data_in_p_tb = 6'b110011; //TODO: Implementme! (making everything the same right now)
            end
        end
    end

    always @(*) begin
        rx_data_in_n_tb <= ~rx_data_in_p_tb;
    end
    //Implement DAC interface
    initial
        begin: TX_DATA_GEN
            dac_valid_tb = 1'b0;
            dac_data_i1_tb = 1'b0;
            dac_data_q1_tb = 1'b0;
            dac_data_i2_tb = 1'b0;
            dac_data_q2_tb = 1'b0;
    forever
        begin
            //Transmitter IP is synchronized to clk, which is synchronized to the differential rx_clk_in_p
            if(ADC_RXTX_1_MODE == 1) begin
                @(posedge clk_tb) //This also serves to clock out the 2nd two frames (I/Q, 5:0)
                #1
                dac_data_i1_tb = 12'b101010110110;
                dac_data_q1_tb = 12'b001001100010;
                dac_valid_tb = 1'b1; //This preps the dev_if logic to take in the data

                @(posedge clk_tb) //When this occurs, the gets taken in, and later clocked out on I/Q, 11:6
                #1
                dac_valid_tb = 1'b0; //With the data taken in, valid must go low again

                @(posedge clk_tb) //This is just here so we can send alternating data packets
                #1
                dac_data_i1_tb = 12'b110011001100;
                dac_data_q1_tb = 12'b101010100001;
                dac_valid_tb = 1'b1;

                @(posedge clk_tb)
                #1
                dac_valid_tb = 1'b0;

            end else begin
                //Not implemented atm
                dac_data_i1_tb = 12'b000000000000;
                dac_data_q1_tb = 12'b000000000000;
                dac_valid_tb = 1'b0;
            end
        end
    end

    axi_ad9361_dev_if #(
        .PCORE_BUFTYPE (PCORE_BUFTYPE))
    i_dev_if (
        .rx_clk_in_p (rx_clk_in_p_tb),
        .rx_clk_in_n (rx_clk_in_n_tb),
        .rx_frame_in_p (rx_frame_in_p_tb),
        .rx_frame_in_n (rx_frame_in_n_tb),
        .rx_data_in_p (rx_data_in_p_tb),
        .rx_data_in_n (rx_data_in_n_tb),
        .tx_clk_out_p (tx_clk_out_p_tb),
        .tx_clk_out_n (tx_clk_out_n_tb),
        .tx_frame_out_p (tx_frame_out_p_tb),
        .tx_frame_out_n (tx_frame_out_n_tb),
        .tx_data_out_p (tx_data_out_p_tb),
        .tx_data_out_n (tx_data_out_n_tb),
        .clk (clk_tb),
        .adc_valid (adc_valid_s_tb),
        .adc_data_i1 (adc_data_i1_tb),
        .adc_data_q1 (adc_data_q1_tb),
        .adc_data_i2 (adc_data_i2_tb),
        .adc_data_q2 (adc_data_q2_tb),
        .adc_status (adc_status_tb),
        .adc_r1_mode (adc_r1_mode_tb),
        .dac_valid (dac_valid_tb),
        .dac_data_i1 (dac_data_i1_tb),
        .dac_data_q1 (dac_data_q1_tb),
        .dac_data_i2 (dac_data_i2_tb),
        .dac_data_q2 (dac_data_q2_tb),
        .dac_r1_mode (dac_r1_mode_tb),
        .dev_dbg_trigger (dev_dbg_trigger_tb),
        .dev_dbg_data (dev_dbg_data_tb)
    );

endmodule