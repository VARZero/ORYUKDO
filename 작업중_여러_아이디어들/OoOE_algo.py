# Parameters
rs_channels = 5 
logical_reg_num = 15

# Registers
prrbmt = [[1, 1, []], ] # 0번 레지스터는 zero 레지스터
rob = list()
rs = list()

# Sim value
cycle = 0

# Logical Opcodes [Opcode Family, Action Opcode, Modify Register]
    # After Decoder Values
op2mop = { # todo: IMM 처리
    "ADD": [0, 0, 1],
    "SUB": [0, 1, 1],
    "MUL": [1, 0, 1],
    "DIV": [2, 0, 1],
    "SHIFT": [0, 2, 1],
    "B": [3, 0, 0],
    "J": [3, 1, 0],
    "LD": [4, 0, 1],
    "ST": [4, 1, 0]
}
logical_reg_list = [0]

def initialize_sys():
    for i in range(rs_channels):
        rs.append(list())
    for i in range(logical_reg_num):
        logical_reg_list.append(None)

# NEW ENTRY LOGIC's action - 새로운 명령이 인가되면
    # ROB 엔트리를 추가하고, 필요시 PRRBMT 엔트리 추가
    # Todo: 입력에 Branch 요소 넣기(분기예측)
def new_entry_logic_inst(pc, opcode, logical_reg, opr1, opr2):
    new_rob_opr1 = logical_reg_list[opr1]
    new_rob_opr2 = logical_reg_list[opr2]

    phy_reg_no = len(prrbmt)
    require_new_reg = op2mop[opcode][2]
    if (require_new_reg):
        prrbmt.append([1, 0, list()]) # new entry on PRRBMT
        logical_reg_list[logical_reg] = phy_reg_no if (logical_reg != 0) else 0
        # 명령이 들어올때, 레지스터에 쓰지 않는 경우
        # logical reg는 항상 0
    
    rob_entry_no = len(rob)
    if (new_rob_opr1 == new_rob_opr2):
        prrbmt_list_update(new_rob_opr1, rob_entry_no)
    else:
        prrbmt_list_update(new_rob_opr1, rob_entry_no)
        prrbmt_list_update(new_rob_opr2, rob_entry_no)
    rob.append({ # new entry on ROB
        "PC": pc,
        "MicroOP": [ op2mop[opcode][0], op2mop[opcode][1] ],
        "LOG_REG": logical_reg if (require_new_reg) else 0,
        "PHY_REG": phy_reg_no if (require_new_reg) else 0,
        "OPR1": new_rob_opr1,
        "OPR2": new_rob_opr2,
        "READY1": prrbmt[new_rob_opr1][1],
        "READY2": prrbmt[new_rob_opr2][1],
        # "BRANCH": ??
        "DONE": 0
    })
    if (prrbmt[new_rob_opr1][1] and prrbmt[new_rob_opr2][1]):
        # 둘다 바로 사용 가능한 경우라면
        go_to_rs(rob_entry_no)

# ROB's action (update: ->ROB, PRRBMT->ROB)
def rob_entry_update(rob_no, ready_reg):
    rob_data = rob[rob_no]
    if (rob_data["OPR1"] == ready_reg):
        rob_data["READY1"] = 1
    if (rob_data["OPR2"] == ready_reg):
        rob_data["READY2"] = 1
    rob[rob_no] = rob_data # rob update
    
    if (rob_data["READY1"] and rob_data["READY2"]):
        go_to_rs(rob_no)

# ROB's action (done: WB->ROB)
def rob_done(rob_no):
    rob[rob_no]["DONE"] = 1

# PRRBMT's action (WRITE_BACK->PRRBMT)
def wb_prrbmt_req(reg_no):
    prrbmt[reg_no][1] = 1
    for rob_target in prrbmt[reg_no][2]:
        rob_entry_update(rob_target, reg_no)

# PRRBMT's action (ROB->PRRBMT)
def prrbmt_list_update(reg_no, rob_no):
    if (reg_no == 0): return
    prrbmt[reg_no][2].append(rob_no)

# ROB->RS action
def go_to_rs(rob_no):
    rob_data = rob[rob_no]
    rs[rob_data["MicroOP"][0]].append({
        "ROB_NO": rob_no,
        "MicroOP": rob_data["MicroOP"][1],
        "PHY_REG": rob_data["PHY_REG"],
        "OPR1": rob_data["OPR1"],
        "OPR2": rob_data["OPR2"]
    })

# EX 모델링 필요 (이 부분은 알고리즘이 아님 - 시뮬레이터용)
    # 실제로는 Ready를 사용할 듯
    # 여기서는 opcode의 첫번째 요소를 사이클수로 잡기
    # 각 ex 모듈의 동작 사이클을 가지는
rs_cycle = []
for i in range(rs_channels):
    rs_cycle.append(0)
def ex_modeling():
    for i in range(rs_channels):
        rs_cycle[i] += 1
        if (rs_cycle[i] == i):
            rs_cycle[i] = 0
            wb_prrbmt_req(rs[i][0]["PHY_REG"])
            rob_done(rob_no)
            rs[i][0].remove(0)

# 명령 입력 모델링 필요 (이 부분은 알고리즘이 아님 - 시뮬레이터용)
    # Instruction이 들어오는것을 묘사

