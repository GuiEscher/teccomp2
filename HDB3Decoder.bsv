import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import ThreeLevelIO::*;

interface HDB3Decoder;
    interface Put#(Symbol) in;
    interface Get#(Bit#(1)) out;
endinterface

typedef enum {
    IDLE_OR_S1,
    S2,
    S3,
    S4
} State deriving (Bits, Eq, FShow);

module mkHDB3Decoder(HDB3Decoder);
    // Criação dos FIFOs para o pipeline
    Vector#(4, FIFOF#(Symbol)) fifo_buffer <- replicateM(mkPipelineFIFOF);
    Reg#(Bool) last_pulse <- mkReg(False);
    Reg#(State) current_state <- mkReg(IDLE_OR_S1);

    // Conexões entre FIFOs
    for (Integer i = 0; i < 3; i = i + 1)
        mkConnection(toGet(fifo_buffer[i+1]), toPut(fifo_buffer[i]));

    interface in = toPut(fifo_buffer[3]);

    interface Get out;
        method ActionValue#(Bit#(1)) get;
            let symbols = tuple4(fifo_buffer[0].first, fifo_buffer[1].first, fifo_buffer[2].first, fifo_buffer[3].first);
            let result = 0;

            case (current_state) // Determinação da ação com base no estado atual
                IDLE_OR_S1:
                    if (
                        symbols == tuple4(P, Z, Z, P) ||
                        symbols == tuple4(N, Z, Z, N)
                    ) action
                        current_state <= S2;
                        last_pulse <= !last_pulse;
                    endaction else if (
                        (last_pulse && symbols == tuple4(Z, Z, Z, P)) ||
                        (!last_pulse && symbols == tuple4(Z, Z, Z, N))
                    ) action
                        current_state <= S2;
                    endaction else if (tpl_1(symbols) == P || tpl_1(symbols) == N) action
                        result = 1;
                        last_pulse <= (tpl_1(symbols) == P) ? True : False;
                    endaction 
                S2, S3, S4:
                    action
                        // Nos estados S2, S3 e S4, definimos o bit como 0
                        result = 0;
                        current_state <= (current_state == S2) ? S3 : ((current_state == S3) ? S4 : IDLE_OR_S1);
                    endaction
            endcase

            fifo_buffer[0].deq;
            return result;
        endmethod
    endinterface
endmodule
