import GetPut::*;
import FIFOF::*;
import Assert::*;

typedef Bit#(TLog#(32)) Timeslot;

// Interface para o desmarcador E1
interface E1Unframer;
    interface Put#(Bit#(1)) in; // Interface de entrada para bits
    interface Get#(Tuple2#(Timeslot, Bit#(1))) out; // Interface de saída para tuplas (Timeslot, Bit)
endinterface

// Definição dos estados da máquina de estados
typedef enum {
    UNSYNCED, // Estado inicial, não sincronizado
    FIRST_FAS, // Primeiro FAS encontrado
    FIRST_NFAS, // Primeiro NFAS encontrado
    SYNCED // Estado sincronizado
} State deriving (Bits, Eq, FShow);

// Módulo para o desmarcador E1
module mkE1Unframer(E1Unframer);
    // Fila FIFO para armazenar a saída
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    // Registro para armazenar o estado atual da máquina
    Reg#(State) current_state <- mkReg(UNSYNCED);
    // Registro para armazenar o índice do bit atual
    Reg#(Bit#(TLog#(8))) current_bit_index <- mkRegU;
    // Registro para armazenar o Timeslot atual
    Reg#(Timeslot) current_ts <- mkRegU;
    // Registro para armazenar se é a vez do FAS
    Reg#(Bool) fas_turn <- mkRegU;
    // Registro para armazenar o byte atual
    Reg#(Bit#(8)) current_byte <- mkReg(0);

    // Interface de saída para a FIFO
    interface out = toGet(fifo_out);

    // Interface de entrada para bits
    interface Put in;
        method Action put(Bit#(1) b);
            // Cria um novo byte a partir do bit recebido
            let new_byte = {current_byte[6:0], b};

            // Switch para gerenciar os estados
            case (current_state)
                // Estado inicial onde a sincronização não foi obtida
                UNSYNCED:
                    if (new_byte[6:0] == 7'b0011011) action
                        current_state <= FIRST_FAS; // Transição para o estado FIRST_FAS
                        current_bit_index <= 0; // Reinicia o índice do bit
                        current_ts <= 1; // Reinicia o Timeslot
                        fas_turn <= True; // Configura para a vez do FAS
                    endaction
                
                // Estado após encontrar o primeiro FAS    
                FIRST_FAS:
                    if (current_ts == 0 && current_bit_index == 7) action
                        if (new_byte[6] == 1) action
                            current_state <= FIRST_NFAS; // Transição para FIRST_NFAS
                            current_bit_index <= 0; // Reinicia o índice do bit
                            current_ts <= 1; // Reinicia o Timeslot
                            fas_turn <= False; // Configura para a vez do NFAS
                        endaction
                        else action
                            current_state <= UNSYNCED; // Retorna ao estado não sincronizado
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_ts <= current_ts + 1; // Incrementa o Timeslot
                        current_bit_index <= 0; // Reinicia o índice do bit
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1; // Incrementa o índice do bit
                    endaction
                
                // Estado após encontrar o primeiro NFAS
                FIRST_NFAS:
                    if (current_ts == 0 && current_bit_index == 7) action
                        if (new_byte[6:0] == 7'b0011011) action
                            current_state <= SYNCED; // Transição para o estado SYNCED
                            current_bit_index <= 0; // Reinicia o índice do bit
                            current_ts <= 1; // Reinicia o Timeslot
                            fas_turn <= True; // Configura para a vez do FAS
                        endaction
                        else action
                            current_state <= UNSYNCED; // Retorna ao estado não sincronizado
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_ts <= current_ts + 1; // Incrementa o Timeslot
                        current_bit_index <= 0; // Reinicia o índice do bit
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1; // Incrementa o índice do bit
                    endaction
                
                // Estado onde a sincronização foi obtida e mantida
                SYNCED:
                    action
                        if (current_ts == 0 && current_bit_index == 7) action
                            if (fas_turn) action
                                // Próximo é NFAS
                                if (new_byte[6] == 1) action
                                    current_bit_index <= 0; // Reinicia o índice do bit
                                    current_ts <= 1; // Reinicia o Timeslot
                                    fas_turn <= False; // Configura para a vez do NFAS
                                endaction
                                else action
                                    current_state <= UNSYNCED; // Retorna ao estado não sincronizado
                                endaction
                            endaction
                            else action
                                // Próximo é FAS
                                if (new_byte[6:0] == 7'b0011011) action
                                    current_bit_index <= 0; // Reinicia o índice do bit
                                    current_ts <= 1; // Reinicia o Timeslot
                                    fas_turn <= True; // Configura para a vez do FAS
                                endaction
                                else action
                                    current_state <= UNSYNCED; // Retorna ao estado não sincronizado
                                endaction
                            endaction
                        endaction
                        else if (current_bit_index == 7) action
                            current_ts <= current_ts + 1; // Incrementa o Timeslot
                            current_bit_index <= 0; // Reinicia o índice do bit
                        endaction
                        else action
                            current_bit_index <= current_bit_index + 1; // Incrementa o índice do bit
                        endaction

                        // Envia o Timeslot e o bit atual para a FIFO
                        fifo_out.enq(tuple2(current_ts, b));
                    endaction
            endcase

            // Atualiza o byte atual com o novo byte formado
            current_byte <= new_byte;
        endmethod
    endinterface
endmodule
