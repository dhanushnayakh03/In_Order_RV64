# Waveform testbenches. Each run writes waves/<tb>.vcd
#   make            all four
#   make hazard     one (bram | forwarding | hazard | multiplier)
#   make view-hazard   open the VCD in GTKWave with the saved signal layout
SRC   = ../src
VFLAGS = -g2001 -I$(SRC)
TBS   = bram forwarding hazard multiplier

DEPS_bram       = $(SRC)/imem.v $(SRC)/dmem.v
DEPS_forwarding = $(SRC)/forwarding_unit.v
DEPS_hazard     = $(SRC)/hazard_detection.v
DEPS_multiplier = $(SRC)/ex_stage.v $(SRC)/alu.v $(SRC)/branch_cond.v

.PHONY: all clean $(TBS)
all: $(TBS)

$(TBS): %:
	@mkdir -p waves build
	iverilog $(VFLAGS) -o build/tb_$@.vvp tb_$@.v $(DEPS_$@)
	vvp -n build/tb_$@.vvp
	@echo "-> waves/tb_$@.vcd"

view-%:
	gtkwave --rcvar 'do_initial_zoom_fit yes' --rcvar 'splash_disable on' waves/tb_$*.vcd gtkw/tb_$*.gtkw >/dev/null 2>&1 &

clean:
	rm -rf build waves
