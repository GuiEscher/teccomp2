import GetPut::*;
import FIFOF::*;
import Assert::*;

interface HDLCUnframer;
    interface Put#(Bit#(1)) in; 
    interface Get#(Tuple2#(Bool, Bit#(8))) out;
endinterface

typedef enum {
    IDLE,               // Estado ocioso, aguardando o início de um quadro
    PROCESS_FRAME,      // Estado de processamento de bits de um quadro
    CHECK_BIT_STUFFING  // Estado para verificação de bit stuffing
} FrameState deriving (Eq, Bits, FShow);

module mkHDLCUnframer(HDLCUnframer);
    // FIFO para armazenar bytes de saída juntamente com um indicador de início de quadro
    FIFOF#(Tuple2#(Bool, Bit#(8))) fifo_out <- mkFIFOF; 

    // Indicador do início de um novo quadro
    Reg#(Bool) is_start_of_frame <- mkReg(True);  

    // Estado atual da máquina de estados
    Reg#(FrameState) state <- mkReg(IDLE);  

    // Índice para o bit atual dentro de um byte
    Reg#(Bit#(3)) bit_pos <- mkReg(0);  

    // Byte atual sendo construído a partir dos bits recebidos
    Reg#(Bit#(8)) byte_accumulator <- mkRegU;  

    // Registro para armazenar os últimos 8 bits recebidos
    Reg#(Bit#(8)) recent_bit_history <- mkReg(0);  

    // Padrão de flag HDLC usado para identificar início/fim de um quadro
    Bit#(8) hdlc_flag = 8'b01111110;

    interface out = toGet(fifo_out);

    // Interface de entrada para bits
    interface Put in;
        method Action put(Bit#(1) bit_in);
            // Atualiza o histórico de bits recentes com o novo bit recebido
            let updated_bit_history = {bit_in, recent_bit_history[7:1]};
            
            // Próxima posição do bit dentro do byte
            let next_bit_pos = bit_pos + 1;
            
            // Atualiza o byte acumulador com o novo bit
            let updated_byte_accumulator = {bit_in, byte_accumulator[7:1]};
            
            // Próximo estado por padrão é o estado atual
            let next_state = state;
            
            // Verifica se há bit stuffing com base nos bits recentes
            let is_bit_stuffing = updated_bit_history[7:3] == 5'b11111;

            // Logica da máquina de estados
            case (state)
                IDLE:
                    // Transita para o estado de processamento ao detectar o padrão de flag HDLC
                    if (updated_bit_history == hdlc_flag) action
                        next_state = PROCESS_FRAME;
                        next_bit_pos = 0;
                        is_start_of_frame <= True;
                    endaction
                PROCESS_FRAME:
                    action
                        // Se um byte completo foi recebido, envia para o FIFO
                        if (bit_pos == 7) action
                            next_state = is_bit_stuffing ? CHECK_BIT_STUFFING : PROCESS_FRAME;
                            fifo_out.enq(tuple2(is_start_of_frame, updated_byte_accumulator));
                            is_start_of_frame <= False;
                        endaction
                        else if (is_bit_stuffing) action
                            // Transita para o estado de verificação de bit stuffing
                            next_state = CHECK_BIT_STUFFING;
                        endaction
                        byte_accumulator <= updated_byte_accumulator;
                    endaction
                CHECK_BIT_STUFFING:
                    if (bit_in == 1) action
                        // Se detectar um erro ou uma nova flag, retorna ao estado IDLE
                        next_state = IDLE;
                    endaction
                    else action
                        // Se detectar bit stuffing, ignora o bit e continua processando o quadro
                        next_state = PROCESS_FRAME;
                        next_bit_pos = bit_pos;
                    endaction
            endcase
            
            // Atualiza os registros com os valores calculados
            recent_bit_history <= updated_bit_history;
            bit_pos <= next_bit_pos;
            state <= next_state;
        endmethod
    endinterface
endmodule
