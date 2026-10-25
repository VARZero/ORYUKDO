`timescale 1ns/1ps
module tb_oryukdo_result_selector #(parameter int LANES=5,TOKEN_W=37);
    logic [LANES-1:0] i_valid='0,i_ready='0;
    logic [LANES*TOKEN_W-1:0] i_token='0;
    wire [LANES-1:0] o_selected;
    int checked=0;
    logic [31:0] random_state=32'h83497301;
    oryukdo_result_selector #(.LANES(LANES),.TOKEN_W(TOKEN_W)) dut(.*);
    function automatic logic [31:0] random_word();
        random_state=random_state ^ (random_state<<13);
        random_state=random_state ^ (random_state>>17);
        random_state=random_state ^ (random_state<<5);
        return random_state;
    endfunction
    task automatic check;
        logic [LANES-1:0] eligible,legacy,accepted;
        for(int mode=0;mode<3;mode++) begin
            for(int lane=0;lane<LANES;lane++) begin
                case(mode)
                    0: eligible[lane]=1;
                    1: eligible[lane]=i_token[lane*TOKEN_W];
                    2: eligible[lane]=^i_token[lane*TOKEN_W +: TOKEN_W];
                endcase
            end
            // Executable reference: the former serial scheduler loop.
            legacy=i_valid & eligible;
            for(int lane=0;lane<LANES;lane++) for(int prior=0;prior<lane;prior++)
                if(legacy[prior] && i_ready[prior] &&
                   i_token[prior*TOKEN_W +: TOKEN_W]==i_token[lane*TOKEN_W +: TOKEN_W])
                    legacy[lane]=0;
            if((o_selected & eligible)!==legacy)
                $fatal(1,"selection changed valid=%b ready=%b expected=%b got=%b",i_valid,i_ready,legacy,o_selected & eligible);
            accepted=o_selected & eligible & i_ready;
            for(int lane=0;lane<LANES;lane++) if(accepted[lane])
                for(int prior=0;prior<lane;prior++) if(accepted[prior] &&
                    i_token[prior*TOKEN_W +: TOKEN_W]==i_token[lane*TOKEN_W +: TOKEN_W])
                    $fatal(1,"duplicate token accepted");
            checked++;
        end
    endtask
    initial begin
        // Exhaust every valid/ready mask, including blocked earlier duplicates.
        for(int pattern=0;pattern<8;pattern++) begin
            for(int lane=0;lane<LANES;lane++) begin
                case(pattern)
                    0: i_token[lane*TOKEN_W +: TOKEN_W]='0;
                    1: i_token[lane*TOKEN_W +: TOKEN_W]='1;
                    2: i_token[lane*TOKEN_W +: TOKEN_W]=TOKEN_W'(lane);
                    3: i_token[lane*TOKEN_W +: TOKEN_W]=TOKEN_W'(lane%2);
                    4: i_token[lane*TOKEN_W +: TOKEN_W]=TOKEN_W'(lane/2);
                    5: i_token[lane*TOKEN_W +: TOKEN_W]=(TOKEN_W'(lane)<<(TOKEN_W-5)) | TOKEN_W'(3);
                    6: i_token[lane*TOKEN_W +: TOKEN_W]=(TOKEN_W'(lane%2)<<(TOKEN_W-1)) | TOKEN_W'(1);
                    7: i_token[lane*TOKEN_W +: TOKEN_W]=TOKEN_W'((lane==0 || lane==LANES-1)?7:lane);
                endcase
            end
            for(int valid_mask=0;valid_mask<(1<<LANES);valid_mask++)
                for(int ready_mask=0;ready_mask<(1<<LANES);ready_mask++) begin
                    i_valid=LANES'(valid_mask);i_ready=LANES'(ready_mask);#1;check();
                end
        end
        for(int n=0;n<4096;n++) begin
            i_valid=LANES'(random_word());i_ready=LANES'(random_word());
            for(int lane=0;lane<LANES;lane++) begin
                i_token[lane*TOKEN_W +: TOKEN_W]=TOKEN_W'({random_word(),random_word()});
                if(lane>0 && (random_word()%3)==0)
                    i_token[lane*TOKEN_W +: TOKEN_W]=i_token[(lane-1)*TOKEN_W +: TOKEN_W];
            end
            #1;check();
        end
        $display("tb_oryukdo_result_selector PASS lanes=%0d checks=%0d",LANES,checked);$finish;
    end
endmodule
