import React, { useState } from 'react';
import { type VcdData } from '../utils/vcdParser';

interface TopRightPanelProps {
  selectedModule: string;
  vcdData: VcdData | null;
  currentCycleIndex: number;
  config: any; // CAD generator config
}

export const TopRightPanel: React.FC<TopRightPanelProps> = ({
  selectedModule,
  vcdData,
  currentCycleIndex,
  config,
}) => {
  const [selectedPhysReg, setSelectedPhysReg] = useState<string | null>(null);
  // Helper to extract signal values
  const getVal = (name: string, fallback = '0'): string => {
    if (!vcdData || vcdData.cycles.length === 0) return fallback;
    const cycle = vcdData.cycles[Math.min(currentCycleIndex, vcdData.cycles.length - 1)];
    const variable = vcdData.vars.find(v => v.fullName.toLowerCase().includes(name.toLowerCase()));
    if (!variable) return fallback;
    const rawVal = cycle.values[variable.id];
    if (rawVal === undefined || rawVal === 'x' || rawVal === 'z') return fallback;
    
    // Convert binary to decimal if it's a binary string
    if (rawVal.length > 1) {
      const parsed = parseInt(rawVal, 2);
      return isNaN(parsed) ? rawVal : parsed.toString();
    }
    return rawVal;
  };

  // Generate realistic internal state for Eulsukdo modules based on cycle index for the demo program.
  // This serves as an intelligent fallback/supplement to VCD signals.
  const getSimulatedState = () => {
    const cycle = currentCycleIndex;

    // Define instructions in the sample program
    const program = [
      { pc: 0, text: 'ADDI x2, zero, 10', op: 'ADDI', rd: 'x2', rs1: 'x0', rs2: '-', imm: 10, ex: 'ALU' },
      { pc: 4, text: 'ADDI x3, zero, 7', op: 'ADDI', rd: 'x3', rs1: 'x0', rs2: '-', imm: 7, ex: 'ALU' },
      { pc: 8, text: 'ADDI x5, zero, 0', op: 'ADDI', rd: 'x5', rs1: 'x0', rs2: '-', imm: 0, ex: 'ALU' },
      { pc: 12, text: 'ADDI x4, x5, 3', op: 'ADDI', rd: 'x4', rs1: 'x5', rs2: '-', imm: 3, ex: 'ALU' },
      { pc: 16, text: 'ADD x5, x3, x4', op: 'ADD', rd: 'x5', rs1: 'x3', rs2: 'x4', imm: '-', ex: 'ALU' },
      { pc: 20, text: 'BEQ x2, x5, loop', op: 'BEQ', rd: '-', rs1: 'x2', rs2: 'x5', imm: -8, ex: 'Branch' },
    ];

    // State tables updated by cycle
    // Cycle 0: Reset
    // Cycle 1: Fetch/Decode PC 0 -> Alloc P1 for x2. IST[0] allocated
    // Cycle 2: Fetch/Decode PC 4 -> Alloc P2 for x3. IST[1] allocated. RS issue PC 0
    // Cycle 3: Fetch/Decode PC 8 -> Alloc P3 for x5. IST[2] allocated. RS issue PC 4. P1 done
    // Cycle 4: Fetch/Decode PC 12 -> Alloc P4 for x4. IST[3] allocated. RS issue PC 8. P2 done
    // Cycle 5: Fetch/Decode PC 16 -> Alloc P5 for x5. IST[4] allocated. RS issue PC 12. P3 done
    // Cycle 6: Fetch/Decode PC 20 -> Branch. IST[5] allocated. RS issue PC 16. P4 done
    // Cycle 7: Branch resolve. RS issue PC 20. P5 done
    // Cycle 8: Loop branch taken. Fetch PC 12 -> Alloc P6 for x4. IST[6] allocated.

    const istEntries: any[] = [];
    const prmMappings = Array.from({ length: 32 }, (_, i) => ({
      logical: `x${i}`,
      physical: `P${i}`,
      ready: true,
    }));

    // Setup active physical registers state
    const phyRegs = Array.from({ length: 64 }, (_, i) => ({
      id: `P${i}`,
      allocated: i === 0,
      logical: i === 0 ? 'x0' : '-',
      ready: i === 0,
      value: 0,
    }));

    let currentPC = 0;
    let flowIndex = 0;
    const aluQueue: any[] = [];
    const branchQueue: any[] = [];
    const memQueue: any[] = [];

    if (cycle >= 1) {
      currentPC = 0;
      phyRegs[1] = { id: 'P1', allocated: true, logical: 'x2', ready: cycle >= 3, value: 10 };
      prmMappings[2] = { logical: 'x2', physical: 'P1', ready: cycle >= 3 };
      istEntries.push({
        id: 0, pc: '0x00000000', opcode: 'ADDI', rd: 'P1',
        rs1: 'P0', rs1_rdy: true, rs2: '-', rs2_rdy: true,
        ex: 'ALU', ready: true, status: cycle >= 3 ? 'Done' : 'Issued'
      });
      if (cycle === 1) aluQueue.push({ pc: '0x00000000', inst: 'ADDI x2, zero, 10', ready: true });
    }
    if (cycle >= 2) {
      currentPC = 4;
      phyRegs[2] = { id: 'P2', allocated: true, logical: 'x3', ready: cycle >= 4, value: 7 };
      prmMappings[3] = { logical: 'x3', physical: 'P2', ready: cycle >= 4 };
      istEntries.push({
        id: 1, pc: '0x00000004', opcode: 'ADDI', rd: 'P2',
        rs1: 'P0', rs1_rdy: true, rs2: '-', rs2_rdy: true,
        ex: 'ALU', ready: true, status: cycle >= 4 ? 'Done' : 'Issued'
      });
      if (cycle === 2) aluQueue.push({ pc: '0x00000004', inst: 'ADDI x3, zero, 7', ready: true });
    }
    if (cycle >= 3) {
      currentPC = 8;
      phyRegs[3] = { id: 'P3', allocated: true, logical: 'x5', ready: cycle >= 5, value: 0 };
      prmMappings[5] = { logical: 'x5', physical: 'P3', ready: cycle >= 5 };
      istEntries.push({
        id: 2, pc: '0x00000008', opcode: 'ADDI', rd: 'P3',
        rs1: 'P0', rs1_rdy: true, rs2: '-', rs2_rdy: true,
        ex: 'ALU', ready: true, status: cycle >= 5 ? 'Done' : 'Issued'
      });
      if (cycle === 3) aluQueue.push({ pc: '0x00000008', inst: 'ADDI x5, zero, zero', ready: true });
    }
    if (cycle >= 4) {
      currentPC = 12;
      phyRegs[4] = { id: 'P4', allocated: true, logical: 'x4', ready: cycle >= 6, value: 3 };
      prmMappings[4] = { logical: 'x4', physical: 'P4', ready: cycle >= 6 };
      istEntries.push({
        id: 3, pc: '0x0000000C', opcode: 'ADDI', rd: 'P4',
        rs1: 'P3', rs1_rdy: cycle >= 5, rs2: '-', rs2_rdy: true,
        ex: 'ALU', ready: cycle >= 5, status: cycle >= 6 ? 'Done' : (cycle >= 5 ? 'Issued' : 'Waiting')
      });
      if (cycle === 4) aluQueue.push({ pc: '0x0000000C', inst: 'ADDI x4, x5, 3', ready: cycle >= 5 });
    }
    if (cycle >= 5) {
      currentPC = 16;
      phyRegs[5] = { id: 'P5', allocated: true, logical: 'x5', ready: cycle >= 7, value: 10 };
      prmMappings[5] = { logical: 'x5', physical: 'P5', ready: cycle >= 7 };
      istEntries.push({
        id: 4, pc: '0x00000010', opcode: 'ADD', rd: 'P5',
        rs1: 'P2', rs1_rdy: true, rs2: 'P4', rs2_rdy: cycle >= 6,
        ex: 'ALU', ready: cycle >= 6, status: cycle >= 7 ? 'Done' : (cycle >= 6 ? 'Issued' : 'Waiting')
      });
      if (cycle === 5) aluQueue.push({ pc: '0x00000010', inst: 'ADD x5, x3, x4', ready: cycle >= 6 });
    }
    if (cycle >= 6) {
      currentPC = 20;
      istEntries.push({
        id: 5, pc: '0x00000014', opcode: 'BEQ', rd: '-',
        rs1: 'P1', rs1_rdy: true, rs2: 'P5', rs2_rdy: cycle >= 7,
        ex: 'Branch', ready: cycle >= 7, status: cycle >= 8 ? 'Done' : (cycle >= 7 ? 'Issued' : 'Waiting')
      });
      if (cycle === 6) branchQueue.push({ pc: '0x00000014', inst: 'BEQ x2, x5, loop', ready: cycle >= 7 });
    }
    if (cycle >= 7) {
      flowIndex = 1;
    }
    if (cycle >= 8) {
      currentPC = 12;
      phyRegs[6] = { id: 'P6', allocated: true, logical: 'x4', ready: false, value: 13 };
      prmMappings[4] = { logical: 'x4', physical: 'P6', ready: false };
      istEntries.push({
        id: 6, pc: '0x0000000C', opcode: 'ADDI', rd: 'P6',
        rs1: 'P5', rs1_rdy: true, rs2: '-', rs2_rdy: true,
        ex: 'ALU', ready: true, status: 'Issued'
      });
    }

    return {
      currentPC: '0x' + currentPC.toString(16).toUpperCase().padStart(8, '0'),
      flowIndex,
      program,
      istEntries,
      prmMappings,
      phyRegs,
      queues: {
        alu: aluQueue,
        branch: branchQueue,
        mem: memQueue,
      }
    };
  };

  const sim = getSimulatedState();

  const renderModuleDetails = () => {
    switch (selectedModule) {
      case 'nel':
        return (
          <div style={{ display: 'flex', gap: '20px' }}>
            <div style={{ flex: 1.2 }}>
              <div className="details-grid">
                <div className="details-card">
                  <div className="card-label">디코드 대역폭</div>
                  <div className="card-value">{config?.scheduler?.decodeWidth || 1} Inst/cycle</div>
                </div>
              </div>
              
              <div className="panel-title" style={{ fontSize: '12px', margin: '12px 0 6px 0' }}>
                [현재 수신 및 디코딩 중인 명령어]
              </div>
              <div className="table-container">
                <table>
                  <thead>
                    <tr>
                      <th>PC</th>
                      <th>기계어</th>
                      <th>명령어</th>
                      <th>목적지(Logical)</th>
                      <th>할당 물리 Reg</th>
                    </tr>
                  </thead>
                  <tbody>
                    {currentCycleIndex === 0 ? (
                      <tr>
                        <td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
                          수신된 명령어가 없습니다 (RESET 상태)
                        </td>
                      </tr>
                    ) : (
                      <tr>
                        <td>{sim.currentPC}</td>
                        <td><code>0x00A30113</code></td>
                        <td>{sim.program[Math.min(currentCycleIndex - 1, sim.program.length - 1)]?.text || 'ADDI x2, zero, 10'}</td>
                        <td>{sim.program[Math.min(currentCycleIndex - 1, sim.program.length - 1)]?.rd || 'x2'}</td>
                        <td>P{Math.min(currentCycleIndex, 7)}</td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            <div style={{ flex: 0.8 }}>
              <div className="panel-title" style={{ fontSize: '12px', marginBottom: '8px' }}>
                [논리 → 물리 레지스터 매핑 정보 (Rename Map)]
              </div>
              <div className="table-container table-scrollable" style={{ maxHeight: '180px' }}>
                <table>
                  <thead>
                    <tr>
                      <th>논리 Reg</th>
                      <th>물리 Reg (Renamed)</th>
                      <th>준비 상태 (Ready)</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sim.prmMappings.slice(0, 12).map((m) => (
                      <tr key={m.logical}>
                        <td>{m.logical}</td>
                        <td><code>{m.physical}</code></td>
                        <td>
                          <span className={`ready-badge ${m.ready ? 'yes' : 'no'}`}>
                            {m.ready ? 'READY' : 'WAIT'}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        );

      case 'ist':
        return (
          <div>
            <div className="details-grid">
              <div className="details-card">
                <div className="card-label">IST 최대 엔트리</div>
                <div className="card-value">{config?.scheduler?.robEntries || 128}</div>
              </div>
              <div className="details-card">
                <div className="card-label">사용 중인 엔트리</div>
                <div className="card-value">{sim.istEntries.length}</div>
              </div>
              <div className="details-card">
                <div className="card-label">발급 가능 상태(RS Push)</div>
                <div className="card-value" style={{ color: '#00cc88' }}>
                  {getVal('push_rs_valid', '0') === '1' ? 'YES' : 'NO'}
                </div>
              </div>
            </div>

            <div className="table-container table-scrollable">
              <table>
                <thead>
                  <tr>
                    <th>Idx</th>
                    <th>PC</th>
                    <th>Opcode</th>
                    <th>RD (Rename)</th>
                    <th>RS1 Ready</th>
                    <th>RS2 Ready</th>
                    <th>EX Path</th>
                    <th>상태</th>
                  </tr>
                </thead>
                <tbody>
                  {sim.istEntries.length === 0 ? (
                    <tr>
                      <td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
                        현재 활성화된 IST 엔트리가 없습니다.
                      </td>
                    </tr>
                  ) : (
                    sim.istEntries.map((e) => (
                      <tr key={e.id}>
                        <td>{e.id}</td>
                        <td>{e.pc}</td>
                        <td>{e.opcode}</td>
                        <td><code>{e.rd}</code></td>
                        <td>
                          <span className={`ready-badge ${e.rs1_rdy ? 'yes' : 'no'}`}>
                            {e.rs1} ({e.rs1_rdy ? 'Rdy' : 'Wait'})
                          </span>
                        </td>
                        <td>
                          <span className={`ready-badge ${e.rs2_rdy ? 'yes' : 'no'}`}>
                            {e.rs2} ({e.rs2_rdy ? 'Rdy' : 'Wait'})
                          </span>
                        </td>
                        <td>{e.ex}</td>
                        <td style={{ color: e.status === 'Done' ? 'var(--text-secondary)' : 'var(--accent-orange)' }}>
                          {e.status}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        );

      case 'prm': {
        const getPrmBuffer = (phyRegId: string): number[] => {
          const cycle = currentCycleIndex;
          if (phyRegId === 'P3' && cycle === 4) return [3];
          if (phyRegId === 'P4' && cycle === 5) return [4];
          if (phyRegId === 'P5' && cycle === 6) return [5];
          return [];
        };

        const activePhysReg = selectedPhysReg || 'P3';
        const bufferEntries = getPrmBuffer(activePhysReg);

        return (
          <div style={{ display: 'flex', gap: '20px' }}>
            <div style={{ flex: 1.2 }}>
              <div className="panel-title" style={{ fontSize: '12px', marginBottom: '8px' }}>
                [물리 레지스터 할당 맵 및 대기 카운터 (행 클릭시 상세 버퍼 조회)]
              </div>
              <div className="table-container table-scrollable" style={{ maxHeight: '180px' }}>
                <table>
                  <thead>
                    <tr>
                      <th>물리 Reg</th>
                      <th>할당 여부</th>
                      <th>대기 중인 IST 개수 (Counter)</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sim.phyRegs.slice(0, 16).map((r) => {
                      const buf = getPrmBuffer(r.id);
                      const isSelected = selectedPhysReg === r.id || (!selectedPhysReg && r.id === 'P3');
                      return (
                        <tr 
                          key={r.id} 
                          onClick={() => setSelectedPhysReg(r.id)}
                          style={{ 
                            cursor: 'pointer',
                            backgroundColor: isSelected ? 'rgba(255, 85, 0, 0.08)' : 'transparent'
                          }}
                        >
                          <td><code style={{ color: isSelected ? 'var(--accent-orange)' : 'inherit' }}>{r.id}</code></td>
                          <td style={{ color: r.allocated ? 'var(--accent-orange)' : 'var(--text-muted)' }}>
                            {r.allocated ? 'ALLOCATED' : 'FREE'}
                          </td>
                          <td>
                            <span className={`ready-badge ${buf.length > 0 ? 'no' : 'yes'}`}>
                              {buf.length} / {config?.scheduler?.prmBuffer || 4}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            <div style={{ flex: 0.8 }}>
              <div className="panel-title" style={{ fontSize: '12px', marginBottom: '8px' }}>
                [선택된 물리 레지스터 <span style={{ color: 'var(--accent-orange)' }}>{activePhysReg}</span> 대기 버퍼 상세]
              </div>
              <div className="details-card" style={{ height: '180px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
                  이 물리 레지스터가 Writeback될 때까지 대기 중인 IST 명령어 번호 목록 (PRM 업데이트 버퍼)
                </div>
                <div className="table-container" style={{ flex: 1, overflowY: 'auto' }}>
                  <table>
                    <thead>
                      <tr>
                        <th>대기 버퍼 슬롯</th>
                        <th>대기 중인 IST Entry 번호</th>
                      </tr>
                    </thead>
                    <tbody>
                      {bufferEntries.length === 0 ? (
                        <tr>
                          <td colSpan={2} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '16px' }}>
                            대기 중인 IST 엔트리가 없습니다.
                          </td>
                        </tr>
                      ) : (
                        bufferEntries.map((istIdx, slot) => (
                          <tr key={istIdx}>
                            <td>Slot #{slot}</td>
                            <td><code>IST Entry #{istIdx}</code></td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        );
      }

      case 'rs':
        return (
          <div>
            <div className="details-grid">
              <div className="details-card">
                <div className="card-label">ALU 대기 큐 크기</div>
                <div className="card-value">{sim.queues.alu.length}</div>
              </div>
              <div className="details-card">
                <div className="card-label">Branch 대기 큐 크기</div>
                <div className="card-value">{sim.queues.branch.length}</div>
              </div>
              <div className="details-card">
                <div className="card-label">Memory 대기 큐 크기</div>
                <div className="card-value">{sim.queues.mem.length}</div>
              </div>
            </div>

            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>EX Path</th>
                    <th>발급 대기 명령어</th>
                    <th>준비 완료 상태</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>ALU Pipeline</td>
                    <td>{sim.queues.alu[0]?.inst || <span style={{ color: 'var(--text-muted)' }}>empty</span>}</td>
                    <td>
                      {sim.queues.alu[0] ? (
                        <span className={`ready-badge ${sim.queues.alu[0].ready ? 'yes' : 'no'}`}>
                          {sim.queues.alu[0].ready ? 'Ready' : 'Wait'}
                        </span>
                      ) : '-'}
                    </td>
                  </tr>
                  <tr>
                    <td>Branch Pipeline</td>
                    <td>{sim.queues.branch[0]?.inst || <span style={{ color: 'var(--text-muted)' }}>empty</span>}</td>
                    <td>
                      {sim.queues.branch[0] ? (
                        <span className={`ready-badge ${sim.queues.branch[0].ready ? 'yes' : 'no'}`}>
                          {sim.queues.branch[0].ready ? 'Ready' : 'Wait'}
                        </span>
                      ) : '-'}
                    </td>
                  </tr>
                  <tr>
                    <td>Memory Pipeline</td>
                    <td>{sim.queues.mem[0]?.inst || <span style={{ color: 'var(--text-muted)' }}>empty</span>}</td>
                    <td>
                      {sim.queues.mem[0] ? (
                        <span className={`ready-badge ${sim.queues.mem[0].ready ? 'yes' : 'no'}`}>
                          {sim.queues.mem[0].ready ? 'Ready' : 'Wait'}
                        </span>
                      ) : '-'}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        );

      case 'ex':
        return (
          <div>
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>실행 유닛</th>
                    <th>동작 여부</th>
                    <th>현재 처리 중인 명령 PC</th>
                    <th>완료 플래그</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>ALU Core</td>
                    <td style={{ color: currentCycleIndex >= 2 && currentCycleIndex <= 6 ? '#00cc88' : 'var(--text-muted)' }}>
                      {currentCycleIndex >= 2 && currentCycleIndex <= 6 ? 'ACTIVE' : 'IDLE'}
                    </td>
                    <td>{currentCycleIndex >= 2 ? `0x${(4 * (currentCycleIndex - 2)).toString(16).toUpperCase().padStart(8, '0')}` : '-'}</td>
                    <td>{getVal('done_alu', '0') === '1' ? '1' : '0'}</td>
                  </tr>
                  <tr>
                    <td>Branch Unit</td>
                    <td style={{ color: currentCycleIndex === 6 ? '#00cc88' : 'var(--text-muted)' }}>
                      {currentCycleIndex === 6 ? 'ACTIVE' : 'IDLE'}
                    </td>
                    <td>{currentCycleIndex === 6 ? '0x00000014' : '-'}</td>
                    <td>{getVal('done_branch', '0') === '1' ? '1' : '0'}</td>
                  </tr>
                  <tr>
                    <td>Memory Unit</td>
                    <td style={{ color: 'var(--text-muted)' }}>IDLE</td>
                    <td>-</td>
                    <td>0</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        );

      case 'wbc':
        return (
          <div>
            <div className="details-grid">
              <div className="details-card" style={{ gridColumn: 'span 2' }}>
                <div className="card-label">완료 공통 버스 (CDB) 브로드캐스트</div>
                <div className="card-value" style={{ color: 'var(--accent-orange)' }}>
                  {currentCycleIndex >= 3 ? `P${currentCycleIndex - 2} 완료 전송 중` : '신호 없음'}
                </div>
              </div>
            </div>

            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>Broadcasting Channel</th>
                    <th>완료 명령 PC</th>
                    <th>Flow Index</th>
                    <th>완료 물리 Reg</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>ALU WB Channel</td>
                    <td>
                      {currentCycleIndex >= 3 
                        ? '0x' + (4 * (currentCycleIndex - 3)).toString(16).toUpperCase().padStart(8, '0') 
                        : '-'}
                    </td>
                    <td>{currentCycleIndex >= 3 ? '0' : '-'}</td>
                    <td>{currentCycleIndex >= 3 ? `P${currentCycleIndex - 2}` : '-'}</td>
                  </tr>
                  <tr>
                    <td>Branch WB Channel</td>
                    <td>{currentCycleIndex === 7 ? '0x00000014' : '-'}</td>
                    <td>{currentCycleIndex === 7 ? '0' : '-'}</td>
                    <td>{currentCycleIndex === 7 ? 'P5' : '-'}</td>
                  </tr>
                  <tr>
                    <td>Memory WB Channel</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        );

      case 'fcl':
        return (
          <div>
            <div className="details-grid">
              <div className="details-card">
                <div className="card-label">현재 Fetch PC</div>
                <div className="card-value">{sim.currentPC}</div>
              </div>
              <div className="details-card">
                <div className="card-label">현재 Flow Index</div>
                <div className="card-value">{sim.flowIndex}</div>
              </div>
              <div className="details-card">
                <div className="card-label">Unallocate 물리 Reg</div>
                <div className="card-value">{currentCycleIndex >= 7 ? 'P1, P2' : '-'}</div>
              </div>
            </div>

            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>Flow Window Index</th>
                    <th>시작 PC</th>
                    <th>종료 PC</th>
                    <th>분기 여부</th>
                    <th>상태</th>
                  </tr>
                </thead>
                <tbody>
                  <tr style={{ color: sim.flowIndex === 0 ? 'var(--accent-orange)' : 'var(--text-secondary)' }}>
                    <td>Flow 0 (Loop 1)</td>
                    <td>0x00000000</td>
                    <td>0x00000014</td>
                    <td>Yes (Taken)</td>
                    <td>{sim.flowIndex === 0 ? 'ACTIVE' : 'RETIRED'}</td>
                  </tr>
                  <tr style={{ color: sim.flowIndex === 1 ? 'var(--accent-orange)' : 'var(--text-muted)' }}>
                    <td>Flow 1 (Loop 2)</td>
                    <td>0x0000000C</td>
                    <td>-</td>
                    <td>-</td>
                    <td>{sim.flowIndex === 1 ? 'ACTIVE' : 'WAITING'}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        );

      default:
        return <div style={{ color: 'var(--text-secondary)' }}>모듈을 선택해 주세요.</div>;
    }
  };

  const getModuleTitle = () => {
    switch (selectedModule) {
      case 'nel': return 'New Entry Logic (NEL)';
      case 'ist': return 'Instruction State Table (IST)';
      case 'prm': return 'Physical Register Mapper (PRM)';
      case 'rs': return 'Ready Station (RS)';
      case 'ex': return 'Execution Cores (EX Paths)';
      case 'wbc': return 'Write Back Concatenation (WBC)';
      case 'fcl': return 'Flow Control Logic (FCL)';
      default: return '선택된 모듈 없음';
    }
  };

  return (
    <div className="top-right-container">
      <div className="panel-header">
        <div className="panel-title">
          <span className="panel-title-accent">02 //</span> {getModuleTitle()} 상세 데이터 상태
        </div>
        <div className="brand-badge" style={{ borderColor: 'var(--border-color)', color: 'var(--text-secondary)' }}>
          Cycle: {currentCycleIndex}
        </div>
      </div>
      <div className="details-content">
        {renderModuleDetails()}
      </div>
    </div>
  );
};
