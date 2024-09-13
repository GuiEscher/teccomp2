import TriState::*;
import GetPut::*;
import BUtils::*;
import FIFOF::*;
import Assert::*;

// Define o número de ciclos por símbolo
typedef 32 CyclesPerSymbol;

// Define o tipo enum Symbol com três estados: N (negativo), Z (zero), P (positivo)
typedef enum { N, Z, P } Symbol deriving (Eq, Bits, FShow);

// Interface para os pinos de entrada e saída de três níveis (ThreeLevelIOPins)
interface ThreeLevelIOPins;
    // Método para pino de transmissão positiva (sempre pronto)
    (* always_ready *)
    method Inout#(Bit#(1)) txp;
    
    // Método para pino de transmissão negativa (sempre pronto)
    (* always_ready *)
    method Inout#(Bit#(1)) txn;
    
    // Método para receber dados, onde os pinos de entrada podem ser combinados (sempre pronto e habilitado)
    (* always_ready, always_enabled, prefix="" *)
    method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);

    // Método de depuração (sempre pronto)
    (* always_ready *)
    method Bool dbg1;
endinterface

// Interface principal para a IO de três níveis
interface ThreeLevelIO;
    interface ThreeLevelIOPins pins; // Interface para os pinos
    interface Put#(Symbol) in;       // Interface de entrada para colocar símbolos
    interface Get#(Symbol) out;      // Interface de saída para obter símbolos
endinterface

// Módulo que implementa a interface ThreeLevelIO
module mkThreeLevelIO#(Bool sync_to_line_clock)(ThreeLevelIO);
    // Valor máximo do contador baseado nos ciclos por símbolo
    LBit#(CyclesPerSymbol) max_counter_value = fromInteger(valueOf(CyclesPerSymbol) - 1);
    Reg#(LBit#(CyclesPerSymbol)) reset_counter_value <- mkReg(max_counter_value); // Valor do contador de reset
    Reg#(LBit#(CyclesPerSymbol)) counter <- mkReg(max_counter_value);            // Contador principal

    // Registradores para os pinos de transmissão e habilitação do buffer
    Reg#(Bit#(1)) txp_reg <- mkReg(0);
    Reg#(Bit#(1)) txn_reg <- mkReg(0);
    Reg#(Bool) tx_enable <- mkReg(False);
    TriState#(Bit#(1)) txp_buffer <- mkTriState(tx_enable, txp_reg);
    TriState#(Bit#(1)) txn_buffer <- mkTriState(tx_enable, txn_reg);

    // FIFO para os símbolos de transmissão
    FIFOF#(Symbol) tx_fifo <- mkFIFOF;

    // Flag para indicar se uma saída foi produzida
    Reg#(Bool) output_produced <- mkReg(False);
    
    // Assertiva contínua para garantir que o FIFO não fique vazio
    continuousAssert(!output_produced || tx_fifo.notEmpty, "TX FIFO was not fed quickly enough");

    // Regra para a produção da saída
    rule output_production;
        // Obtém o primeiro nível do FIFO
        let level = tx_fifo.first;

        // Se o contador está abaixo da metade, o nível retorna a zero
        let mid_counter_value = max_counter_value >> 1;
        if (counter < mid_counter_value) begin
            level = Z;
        end

        // Define os valores dos pinos de transmissão e habilitação baseados no nível
        case (level)
            N: action
                    txp_reg <= 0;
                    txn_reg <= 1;
                    tx_enable <= True;
                endaction
            Z: action
                    txp_reg <= 0;
                    txn_reg <= 0;
                    tx_enable <= False;
                endaction
            P: action
                    txp_reg <= 1;
                    txn_reg <= 0;
                    tx_enable <= True;
                endaction
        endcase

        // Decrementa o FIFO quando o contador chega a zero
        if (counter == 0) begin
            tx_fifo.deq;
        end

        // Indica que uma saída foi produzida
        output_produced <= True;
    endrule

    // Registradores para sincronizar a recepção
    Reg#(Bit#(3)) rxp_sync <- mkReg('b111);
    Reg#(Bit#(3)) rxn_sync <- mkReg('b111);
    
    // Fio de leitura para o FIFO de recepção
    RWire#(Symbol) rx_fifo_wire <- mkRWire;
    
    // FIFO para os símbolos de recepção
    FIFOF#(Symbol) rx_fifo <- mkFIFOF;

    // Assertiva contínua para garantir que o FIFO de recepção não fique cheio
    continuousAssert(!isValid(rx_fifo_wire.wget) || rx_fifo.notFull, "RX FIFO was not consumed quickly enough");

    // Regra para enfileirar os dados recebidos no FIFO de recepção
    rule rx_fifo_enq (rx_fifo_wire.wget matches tagged Valid .value);
        rx_fifo.enq(value);
    endrule

    // Implementação dos métodos da interface ThreeLevelIOPins
    interface ThreeLevelIOPins pins;
        method txp = txp_buffer.io;
        method txn = txn_buffer.io;

        // Método de recepção de dados
        method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);
            rxp_sync <= {rxp_n, rxp_sync[2:1]}; // Sincroniza os dados recebidos
            rxn_sync <= {rxn_n, rxn_sync[2:1]};

            // Valor de amostragem baseado no relógio de linha
            let sample_counter_value = sync_to_line_clock ? 0 : 17;
            if (counter == sample_counter_value) begin
                // Define o valor baseado nos sinais de sincronização
                let value = case ({rxp_sync[1], rxn_sync[1]})
                    2'b00: Z;
                    2'b11: Z;
                    2'b01: P;
                    2'b10: N;
                endcase;
                rx_fifo_wire.wset(value); // Escreve o valor no fio
            end

            // Atualiza o contador
            counter <= counter == 0 ? reset_counter_value : counter - 1;

            // Ajusta o valor de reset baseado nas bordas detectadas
            if (sync_to_line_clock) begin
                let pos_edge_detected = rxp_sync[1:0] == 'b01 || rxn_sync[1:0] == 'b01;

                if (pos_edge_detected) begin
                    let expected_counter_value = reset_counter_value >> 2;

                    if (counter < expected_counter_value) begin
                        reset_counter_value <= max_counter_value + 1;
                    end else if (counter > expected_counter_value) begin
                        reset_counter_value <= max_counter_value - 1;
                    end else begin
                        reset_counter_value <= max_counter_value;
                    end
                end
            end
        endmethod

        // Método de depuração que indica se o FIFO está válido
        method dbg1 = isValid(rx_fifo_wire.wget);
    endinterface

    // Interfaces de entrada e saída para comunicação
    interface out = toGet(rx_fifo);
    interface in = toPut(tx_fifo);
endmodule
