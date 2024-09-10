import TriState::*;
import GetPut::*;
import BUtils::*;
import FIFOF::*;
import Assert::*;

typedef 32 CyclesPerSymbol;

interface ThreeLevelIO;
    interface ThreeLevelIOPins pins;
    interface Put#(Symbol) in;
    interface Get#(Symbol) out;
endinterface

typedef enum { N, Z, P } Symbol deriving (Eq, Bits, FShow);

interface ThreeLevelIOPins;
    (* always_ready *)
    method Inout#(Bit#(1)) txp;
    (* always_ready *)
    method Inout#(Bit#(1)) txn;
    (* always_ready, always_enabled, prefix="" *)
    method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);

    (* always_ready *)
    method Bool dbg1;
endinterface

module mkThreeLevelIO#(Bool sync_to_line_clock)(ThreeLevelIO);
    LBit#(CyclesPerSymbol) max_counter_value = fromInteger(valueOf(CyclesPerSymbol) - 1);
    Reg#(LBit#(CyclesPerSymbol)) reset_counter_value <- mkReg(max_counter_value);
    Reg#(LBit#(CyclesPerSymbol)) counter <- mkReg(max_counter_value);

    Reg#(Bit#(1)) txp_reg <- mkReg(0);
    Reg#(Bit#(1)) txn_reg <- mkReg(0);
    Reg#(Bool) tx_enable <- mkReg(False);
    TriState#(Bit#(1)) txp_buffer <- mkTriState(tx_enable, txp_reg);
    TriState#(Bit#(1)) txn_buffer <- mkTriState(tx_enable, txn_reg);

    FIFOF#(Symbol) tx_fifo <- mkFIFOF;

    Reg#(Bool) output_produced <- mkReg(False);
    continuousAssert(!output_produced || tx_fifo.notEmpty, "TX FIFO was not fed quickly enough");

    rule output_production;
        let level = tx_fifo.first;

        let mid_counter_value = max_counter_value >> 1;
        if (counter < mid_counter_value)  // Return-to-zero
            level = Z;

        case (level)
            N:
                action
                    txp_reg <= 0;
                    txn_reg <= 1;
                    tx_enable <= True;
                endaction
            Z:
                action
                    txp_reg <= 0;
                    txn_reg <= 0;
                    tx_enable <= False;
                endaction
            P:
                action
                    txp_reg <= 1;
                    txn_reg <= 0;
                    tx_enable <= True;
                endaction
        endcase

        if (counter == 0) begin
            tx_fifo.deq;
        end

        output_produced <= True;
    endrule

    Reg#(Bit#(3)) rxp_sync <- mkReg('b111);
    Reg#(Bit#(3)) rxn_sync <- mkReg('b111);
    RWire#(Symbol) rx_fifo_wire <- mkRWire;
    FIFOF#(Symbol) rx_fifo <- mkFIFOF;

    continuousAssert(!isValid(rx_fifo_wire.wget) || rx_fifo.notFull, "RX FIFO was not consumed quickly enough");

    rule rx_fifo_enq (rx_fifo_wire.wget matches tagged Valid .value);
        rx_fifo.enq(value);
    endrule

    interface ThreeLevelIOPins pins;
        method txp = txp_buffer.io;
        method txn = txn_buffer.io;

        method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);
            rxp_sync <= {rxp_n, rxp_sync[2:1]};
            rxn_sync <= {rxn_n, rxn_sync[2:1]};

            let sample_counter_value = sync_to_line_clock ? 0 : 17;
            if (counter == sample_counter_value) begin
                let value = case ({rxp_sync[1], rxn_sync[1]})
                    2'b00: Z;
                    2'b11: Z;
                    2'b01: P;
                    2'b10: N;
                endcase;
                rx_fifo_wire.wset(value);
            end

            counter <= counter == 0 ? reset_counter_value : counter - 1;

            if (sync_to_line_clock) begin
                let pos_edge_detected = rxp_sync[1:0] == 'b01 || rxn_sync[1:0] == 'b01;  // {current_bit, previous_bit}

                // Detect positive edge
                if (pos_edge_detected) begin
                    let expected_counter_value = reset_counter_value >> 2;
                    
                    if (counter < expected_counter_value) begin
                        reset_counter_value <= max_counter_value + 1;  // Extend cycle
                    end else if (counter > expected_counter_value) begin
                        reset_counter_value <= max_counter_value - 1;  // Shorten cycle
                    end else begin
                        reset_counter_value <= max_counter_value;  // Maintain cycle
                    end
                end
            end
        endmethod

        method dbg1 = isValid(rx_fifo_wire.wget);
    endinterface

    interface out = toGet(rx_fifo);
    interface in = toPut(tx_fifo);
endmodule
