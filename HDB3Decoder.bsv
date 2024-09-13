import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import ThreeLevelIO::*;

interface HDB3Decoder;
    interface Put#(Symbol) in; // Interface para receber símbolos de entrada
    interface Get#(Bit#(1)) out; // Interface para saída decodificada
endinterface

// Definição dos estados do decodificador HDB3
typedef enum {
    IDLE_OR_S1, // Estado inicial ou estado S1
    S2,         // Estado S2
    S3,         // Estado S3
    S4          // Estado S4
} State deriving (Bits, Eq, FShow);

module mkHDB3Decoder(HDB3Decoder);
    // Criação de um vetor de 4 FIFOs para formar o pipeline de símbolos
    Vector#(4, FIFOF#(Symbol)) fifo_buffer <- replicateM(mkPipelineFIFOF);
    // Registro para armazenar o último pulso recebido (positivo ou negativo)
    Reg#(Bool) last_pulse <- mkReg(False);
    // Registro para armazenar o estado atual do decodificador
    Reg#(State) current_state <- mkReg(IDLE_OR_S1);

    // Conexões entre os FIFOs para formar a cadeia do pipeline
    for (Integer i = 0; i < 3; i = i + 1)
        mkConnection(toGet(fifo_buffer[i+1]), toPut(fifo_buffer[i]));

    // Interface de entrada conectada ao último FIFO da cadeia
    interface in = toPut(fifo_buffer[3]);

    interface Get out;
        method ActionValue#(Bit#(1)) get;
            // Captura os primeiros elementos dos quatro FIFOs no pipeline
            let symbols = tuple4(fifo_buffer[0].first, fifo_buffer[1].first, fifo_buffer[2].first, fifo_buffer[3].first);
            let result = 0; // Inicializa o resultado da decodificação

            // Lógica de decodificação baseada no estado atual
            if (current_state == IDLE_OR_S1) begin
                // Verifica se os símbolos correspondem a uma violação positiva ou negativa
                if (
                    symbols == tuple4(P, Z, Z, P) || // P -> Z -> Z -> P
                    symbols == tuple4(N, Z, Z, N)    // N -> Z -> Z -> N
                ) begin
                    current_state <= S2; // Transição para o estado S2
                    last_pulse <= !last_pulse; // Inverte o último pulso recebido
                end 
                // Verifica se os símbolos indicam uma sequência de três zeros seguida por um pulso
                else if (
                    (last_pulse && symbols == tuple4(Z, Z, Z, P)) || // Z -> Z -> Z -> P (último pulso positivo)
                    (!last_pulse && symbols == tuple4(Z, Z, Z, N))   // Z -> Z -> Z -> N (último pulso negativo)
                ) begin
                    current_state <= S2; // Transição para o estado S2
                end 
                // Verifica se o primeiro símbolo é um pulso (positivo ou negativo)
                else if (tpl_1(symbols) == P || tpl_1(symbols) == N) begin
                    result = 1; // Decodifica como '1'
                    // Atualiza o último pulso recebido com base no símbolo
                    last_pulse <= (tpl_1(symbols) == P) ? True : False;
                end
            end 
            // Se o estado atual for S2, a decodificação é 0 e transita para S3
            else if (current_state == S2) begin
                result = 0;
                current_state <= S3; // Transição para o estado S3
            end 
            // Se o estado atual for S3, a decodificação é 0 e transita para S4
            else if (current_state == S3) begin
                result = 0;
                current_state <= S4; // Transição para o estado S4
            end 
            // Se o estado atual for S4, a decodificação é 0 e retorna para IDLE_OR_S1
            else if (current_state == S4) begin
                result = 0;
                current_state <= IDLE_OR_S1; // Retorna ao estado inicial
            end

            // Remove o símbolo processado do FIFO
            fifo_buffer[0].deq;
            return result; // Retorna o resultado da decodificação
        endmethod
    endinterface
endmodule
