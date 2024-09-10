import GetPut::*;
import FIFOF::*;
import Assert::*;

typedef Bit#(TLog#(32)) Timeslot;

interface E1Unframer;
    interface Put#(Bit#(1)) in;
    interface Get#(Tuple2#(Timeslot, Bit#(1))) out;
endinterface

typedef enum {
    UNSYNCED, 
    FIRST_FAS,
    FIRST_NFAS,
    SYNCED
} State deriving (Bits, Eq, FShow);

module mkE1Unframer(E1Unframer);
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    Reg#(State) current_state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) current_bit_index <- mkRegU;
    Reg#(Timeslot) current_ts <- mkRegU;
    Reg#(Bool) fas_turn <- mkRegU;
    Reg#(Bit#(8)) current_byte <- mkReg(0);

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            let new_byte = {current_byte[6:0], b};

            case (current_state)
                UNSYNCED:
                    action
                        current_state <= (new_byte[6:0] == 7'b0011011) ? FIRST_FAS : UNSYNCED;
                        current_bit_index <= (new_byte[6:0] == 7'b0011011) ? 0 : current_bit_index;
                        current_ts <= (new_byte[6:0] == 7'b0011011) ? 1 : current_ts;
                        fas_turn <= (new_byte[6:0] == 7'b0011011);
                    endaction
                
                FIRST_FAS:
                    action
                        if (current_ts == 0 && current_bit_index == 7) begin
                            current_state <= (new_byte[6] == 1) ? FIRST_NFAS : UNSYNCED;
                            current_bit_index <= (new_byte[6] == 1) ? 0 : current_bit_index;
                            current_ts <= (new_byte[6] == 1) ? 1 : current_ts;
                            fas_turn <= False;
                        end else begin
                            current_ts <= (current_bit_index == 7) ? current_ts + 1 : current_ts;
                            current_bit_index <= (current_bit_index == 7) ? 0 : current_bit_index + 1;
                        end
                    endaction
                
                FIRST_NFAS:
                    action
                        if (current_ts == 0 && current_bit_index == 7) begin
                            current_state <= (new_byte[6:0] == 7'b0011011) ? SYNCED : UNSYNCED;
                            current_bit_index <= (new_byte[6:0] == 7'b0011011) ? 0 : current_bit_index;
                            current_ts <= (new_byte[6:0] == 7'b0011011) ? 1 : current_ts;
                            fas_turn <= (new_byte[6:0] == 7'b0011011);
                        end else begin
                            current_ts <= (current_bit_index == 7) ? current_ts + 1 : current_ts;
                            current_bit_index <= (current_bit_index == 7) ? 0 : current_bit_index + 1;
                        end
                    endaction
                
                SYNCED:
                    action
                        if (current_ts == 0 && current_bit_index == 7) begin
                            if (fas_turn) begin
                                current_state <= (new_byte[6] == 1) ? current_state : UNSYNCED;
                                fas_turn <= (new_byte[6] == 1) ? False : fas_turn;
                            end else begin
                                current_state <= (new_byte[6:0] == 7'b0011011) ? current_state : UNSYNCED;
                                fas_turn <= (new_byte[6:0] == 7'b0011011);
                            end
                            current_bit_index <= 0;
                            current_ts <= 1;
                        end else begin
                            current_ts <= (current_bit_index == 7) ? current_ts + 1 : current_ts;
                            current_bit_index <= (current_bit_index == 7) ? 0 : current_bit_index + 1;
                        end

                        fifo_out.enq(tuple2(current_ts, b));
                    endaction
            endcase

            current_byte <= new_byte;
        endmethod
    endinterface
endmodule
