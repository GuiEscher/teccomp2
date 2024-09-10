import GetPut::*;
import FIFOF::*;
import Assert::*;

interface HDLCUnframer;
    interface Put#(Bit#(1)) in; 
    interface Get#(Tuple2#(Bool, Bit#(8))) out;
endinterface

typedef enum {
    IDLE,               
    PROCESS_FRAME,      
    CHECK_BIT_STUFFING  
} FrameState deriving (Eq, Bits, FShow);

module mkHDLCUnframer(HDLCUnframer);
    // FIFO para armazenar bytes de saída e indicador de início de quadro
    FIFOF#(Tuple2#(Bool, Bit#(8))) fifo_out <- mkFIFOF; 
    Reg#(Bool) start_of_frame <- mkReg(True);  // Registro que indica o início de um quadro
    Reg#(FrameState) current_state <- mkReg(IDLE);  // Registro que mantém o estado atual do módulo
    Reg#(Bit#(3)) bit_index <- mkReg(0);  // Registro para acompanhar o índice do bit atual no byte
    Reg#(Bit#(8)) current_frame_byte <- mkRegU;  // Registro para armazenar o byte atual do quadro
    Reg#(Bit#(8)) recent_bits <- mkReg(0);  // Registro para armazenar os bits recentes

    // Padrão de flag HDLC que é usado para indicar o início ou o fim de um quadro
    Bit#(8) hdlc_flag_pattern = 8'b01111110;

    interface out = toGet(fifo_out);

    // Interface de entrada de bits
    interface Put in;
        method Action put(Bit#(1) b);
            // Atualiza os bits recentes e o byte atual do quadro com o novo bit recebido
            let updated_recent_bits = {b, recent_bits[7:1]};
            let next_bit_index = bit_index + 1;
            let updated_frame_byte = {b, current_frame_byte[7:1]};
            // Define o próximo estado como o estado atual por padrão
            let next_state = current_state;
            // Verifica a presença de bit stuffing com base nos bits recentes
            let check_bit_stuffing = updated_recent_bits[7:3] == 5'b11111;

            // Determina o próximo estado com base no estado atual
            case (current_state)
                IDLE:
                    // Inicia o processamento se detectar o padrão de flag HDLC
                    if (updated_recent_bits == hdlc_flag_pattern) action
                        next_state = PROCESS_FRAME;
                        next_bit_index = 0;
                        start_of_frame <= True;
                    endaction
                PROCESS_FRAME:
                    action
                        // Se o byte estiver completo, coloca o byte no FIFO
                        if (bit_index == 7) action
                            next_state = check_bit_stuffing ? CHECK_BIT_STUFFING : PROCESS_FRAME;
                            fifo_out.enq(tuple2(start_of_frame, updated_frame_byte));
                            start_of_frame <= False;
                        endaction
                        else if (check_bit_stuffing) action
                            // Se necessário, transita para o estado de verificação de bit stuffing
                            next_state = CHECK_BIT_STUFFING;
                        endaction
                        current_frame_byte <= updated_frame_byte;
                    endaction
                CHECK_BIT_STUFFING:
                    if (b == 1) action
                        // Se detectar flag ou erro, retorna ao estado IDLE
                        next_state = IDLE;
                    endaction
                    else action
                        // Se detectar bit stuffing, ignora o bit e continua processando o quadro
                        next_state = PROCESS_FRAME;
                        next_bit_index = bit_index;
                    endaction
            endcase
            // Atualiza os registros com os novos valores calculados
            recent_bits <= updated_recent_bits;
            bit_index <= next_bit_index;
            current_state <= next_state;
        endmethod
    endinterface
endmodule
