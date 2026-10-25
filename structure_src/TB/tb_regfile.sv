`timescale 1ns / 1ps

module tb_regfile();

    parameter       READ_CHANNEL    = 8 ;
    parameter       WRITE_CHANNEL   = 4 ;
    parameter       ENTRIES         = 16;
    parameter       REG_WIDTH       = 32;
    
    localparam      ENTRY_ADDR_WIDTH= $clog2(ENTRIES);

    reg                                          clk;
    reg                                          reset_n;
    reg  [READ_CHANNEL*ENTRY_ADDR_WIDTH-1:0]     i_read_addresses;
    reg  [WRITE_CHANNEL-1:0]                     i_write_wes;
    reg  [WRITE_CHANNEL*ENTRY_ADDR_WIDTH-1:0]    i_write_addresses;
    reg  [WRITE_CHANNEL*REG_WIDTH-1:0]           i_write_data;
    wire [READ_CHANNEL*REG_WIDTH-1:0]            o_read_data;

    integer write_pack = ENTRIES/WRITE_CHANNEL;
    integer read_pack  = ENTRIES/READ_CHANNEL;
    
    regfile #(
        .READ_CHANNEL    (READ_CHANNEL),
        .WRITE_CHANNEL   (WRITE_CHANNEL),
        .ENTRIES         (ENTRIES),
        .REG_WIDTH       (REG_WIDTH)
    ) dut (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    (i_read_addresses),
        .i_write_wes         (i_write_wes),
        .i_write_addresses   (i_write_addresses),
        .i_write_data        (i_write_data),
        .o_read_data         (o_read_data)
    );

    always #5 clk = ~clk;

    initial begin
        #0;
        clk = 0;
        reset_n = 0;
        i_read_addresses = 0;
        i_write_wes = 0;
        i_write_addresses = 0;
        i_write_data = 0;

        repeat(3) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);
        
        // Write 0~MAX
        for (integer write_pack_target = 0; 
            write_pack_target < write_pack; 
            write_pack_target = write_pack_target+1) begin
            
            i_write_wes = 0;
            i_write_addresses = 0;
            i_write_data = 0;
            for (integer w_inter = 0; w_inter < WRITE_CHANNEL; w_inter = w_inter+1) begin
                if ( ( (write_pack_target*WRITE_CHANNEL) + w_inter) == ENTRIES) break;

                i_write_wes[w_inter] = 1'b1;
                i_write_addresses[(ENTRY_ADDR_WIDTH*w_inter) +: ENTRY_ADDR_WIDTH]
                    = (write_pack_target*WRITE_CHANNEL) + w_inter;
                i_write_data[(REG_WIDTH*w_inter) +: REG_WIDTH] 
                    = ~( (write_pack_target*WRITE_CHANNEL) + w_inter );
            end
            @(negedge clk);
        end

        // Read 0~MAX
        for (integer read_pack_target = 0; 
            read_pack_target < read_pack; 
            read_pack_target = read_pack_target+1) begin
            
            i_read_addresses = 0;
            for (integer r_inter = 0; r_inter < READ_CHANNEL; r_inter = r_inter+1) begin
                if ( ( (read_pack_target*READ_CHANNEL) + r_inter) == ENTRIES) break;

                i_read_addresses[(ENTRY_ADDR_WIDTH*r_inter) +: ENTRY_ADDR_WIDTH]
                    = (read_pack_target*READ_CHANNEL) + r_inter;
            end

            @(posedge clk); #1; // Check
            for (integer r_inter = 0; r_inter < READ_CHANNEL; r_inter = r_inter+1) begin
                if ( ( (read_pack_target*READ_CHANNEL) + r_inter) == ENTRIES) break;

                if (o_read_data[(REG_WIDTH*r_inter) +: REG_WIDTH] 
                    === ( ~( (read_pack_target*READ_CHANNEL) + r_inter ) ) ) begin
                    
                    $display("PASS! rf[0x%04h] = 0x%08h", 
                             (read_pack_target*READ_CHANNEL) + r_inter,
                             o_read_data[(REG_WIDTH*r_inter) +: REG_WIDTH]);
                end
                else begin
                    $display("FAIL! rf[0x%04h] = 0x%08h", 
                             (read_pack_target*READ_CHANNEL) + r_inter,
                             o_read_data[(REG_WIDTH*r_inter) +: REG_WIDTH]);
                end
            end
            @(negedge clk);
        end
    
        repeat(3) @(negedge clk);
        $finish;
    end

endmodule
