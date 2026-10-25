export interface VcdVariable {
  id: string;
  name: string;
  fullName: string;
  size: number;
  type: string;
}

export interface VcdCycle {
  cycle: number;
  timestamp: number;
  values: Record<string, string>;
}

export interface VcdData {
  timescale: string;
  vars: VcdVariable[];
  varsById: Record<string, VcdVariable>;
  timeline: number[];
  cycles: VcdCycle[];
  clockVarId: string | null;
}

export function parseVcd(vcdText: string): VcdData {
  const vars: VcdVariable[] = [];
  const varsById: Record<string, VcdVariable> = {};
  let timescale = '1ns';
  let clockVarId: string | null = null;

  const lines = vcdText.split('\n');
  let inDefinitions = true;
  const currentScope: string[] = [];

  const timeline: number[] = [];
  const rawValueChanges = new Map<number, Record<string, string>>();
  let currentTimestamp = 0;
  let currentValues: Record<string, string> = {};

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    if (inDefinitions) {
      if (line.startsWith('$scope')) {
        const parts = line.split(/\s+/);
        // $scope module tb_eulsukdo_1dec3iss $end
        if (parts.length >= 3) {
          currentScope.push(parts[2]);
        }
      } else if (line.startsWith('$upscope')) {
        currentScope.pop();
      } else if (line.startsWith('$var')) {
        const parts = line.split(/\s+/);
        // $var wire 1 ! clk $end or $var wire 32 * fcl_inst_pc [31:0] $end
        if (parts.length >= 5) {
          const type = parts[1];
          const size = parseInt(parts[2], 10);
          const id = parts[3];
          const name = parts[4];
          const fullName = [...currentScope, name].join('.');
          const variable: VcdVariable = { id, name, fullName, size, type };
          vars.push(variable);
          varsById[id] = variable;

          // Auto detect clock: priority to top-level or sub-module 'clk' or 'clock'
          const lowerName = name.toLowerCase();
          if (lowerName === 'clk' || lowerName === 'clock') {
            if (!clockVarId || fullName.split('.').length < varsById[clockVarId].fullName.split('.').length) {
              clockVarId = id;
            }
          }
        }
      } else if (line.startsWith('$timescale')) {
        // Read next line if it doesn't end with $end on same line
        let scaleStr = line.substring(10).replace('$end', '').trim();
        if (!scaleStr && i + 1 < lines.length) {
          scaleStr = lines[i + 1].replace('$end', '').trim();
          i++;
        }
        timescale = scaleStr || '1ns';
      } else if (line.startsWith('$enddefinitions')) {
        inDefinitions = false;
        // Initialize values
        currentValues = {};
        for (const v of vars) {
          currentValues[v.id] = v.size === 1 ? 'x' : 'x'.repeat(v.size);
        }
      }
    } else {
      // Parse timeline and value changes
      if (line.startsWith('#')) {
        const ts = parseInt(line.substring(1), 10);
        if (!timeline.includes(ts)) {
          timeline.push(ts);
        }
        // Save copy of currentValues for the previous timestamp
        rawValueChanges.set(currentTimestamp, { ...currentValues });
        currentTimestamp = ts;
      } else if (line.startsWith('$dumpvars')) {
        // start of initial values
      } else if (line.startsWith('$end')) {
        // end of block
      } else {
        // Parse value change
        if (line.startsWith('b') || line.startsWith('B') || line.startsWith('r') || line.startsWith('R')) {
          const parts = line.split(/\s+/);
          if (parts.length >= 2) {
            const val = parts[0].substring(1);
            const id = parts[1];
            currentValues[id] = val;
          }
        } else {
          // 1 bit change e.g. 0! or 1"
          const val = line[0];
          const id = line.substring(1);
          if (id) {
            currentValues[id] = val;
          }
        }
      }
    }
  }
  // Save final state
  rawValueChanges.set(currentTimestamp, { ...currentValues });

  // If no timeline values were parsed, put 0
  if (timeline.length === 0) {
    timeline.push(0);
    rawValueChanges.set(0, { ...currentValues });
  }

  // Auto-detect clock if not set
  if (!clockVarId) {
    const potentialClks = vars.filter(v => v.name.toLowerCase().includes('clk') || v.name.toLowerCase().includes('clock'));
    if (potentialClks.length > 0) {
      clockVarId = potentialClks[0].id;
    }
  }

  // Calculate cycles based on clock transitions (0 -> 1)
  const cycles: VcdCycle[] = [];
  let cycleCount = 0;
  let lastClockVal: string | null = null;

  // Let's carry forward states to build complete cycles
  let activeValues = { ...rawValueChanges.get(timeline[0])! };

  // Generate cycle list
  if (clockVarId) {
    for (let tIdx = 0; tIdx < timeline.length; tIdx++) {
      const ts = timeline[tIdx];
      const changes = rawValueChanges.get(ts);
      if (changes) {
        activeValues = { ...activeValues, ...changes };
      }

      const clkVal = activeValues[clockVarId];
      if (clkVal === '1' && lastClockVal === '0') {
        // Rising edge! Create a cycle sample
        cycles.push({
          cycle: cycleCount,
          timestamp: ts,
          values: { ...activeValues }
        });
        cycleCount++;
      }
      lastClockVal = clkVal;
    }
  }

  // Fallback if no clock or no rising edge detected
  if (cycles.length === 0) {
    let fallbackCycle = 0;
    let activeValuesFallback = { ...rawValueChanges.get(timeline[0])! };
    for (const ts of timeline) {
      const changes = rawValueChanges.get(ts);
      if (changes) {
        activeValuesFallback = { ...activeValuesFallback, ...changes };
      }
      cycles.push({
        cycle: fallbackCycle,
        timestamp: ts,
        values: { ...activeValuesFallback }
      });
      fallbackCycle++;
    }
  }

  return {
    timescale,
    vars,
    varsById,
    timeline,
    cycles,
    clockVarId
  };
}

// Generate mock VCD data for demo and fallback
export function generateMockVcd(): string {
  return `$date
  Wed Jun 24 06:12:38 2026
$end
$version
  Eulsukdo Mock Sim
$end
$timescale
  10ns
$end
$scope module tb_eulsukdo_1dec3iss $end
$scope module U_EULSUKDO $end
$var reg 1 ! clk $end
$var reg 1 " reset_n $end
$var reg 32 # fcl_inst_pc [31:0] $end
$var reg 1 $ nel_block $end
$var reg 1 % ist_insert_available $end
$var reg 32 & reg_x2 [31:0] $end
$var reg 32 ' reg_x3 [31:0] $end
$var reg 32 ( reg_x4 [31:0] $end
$var reg 32 ) reg_x5 [31:0] $end
$var reg 32 * ex_alu_result [31:0] $end
$var reg 1 + done_alu $end
$var reg 1 , done_branch $end
$upscope $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
0"
bx #
0$
1%
b0 &
b0 '
b0 (
b0 )
bx *
0+
0,
$end
#10
1!
#20
0!
1"
#30
1!
b00000000000000000000000000000000 #
#40
0!
#50
1!
b00000000000000000000000000000100 #
b00000000000000000000000000001010 &
#60
0!
#70
1!
b00000000000000000000000000001000 #
b00000000000000000000000000000111 '
#80
0!
#90
1!
b00000000000000000000000000001100 #
b00000000000000000000000000000000 )
#100
0!
#110
1!
b00000000000000000000000000010000 #
#120
0!
#130
1!
b00000000000000000000000000000011 *
1+
#140
0!
#150
1!
b00000000000000000000000000000011 (
0+
#160
0!
#170
1!
b00000000000000000000000000001010 *
1+
#180
0!
#190
1!
b00000000000000000000000000001010 )
0+
#200
0!
#210
1!
1,
#220
0!
#230
1!
0,
#240
0!
`;
}
