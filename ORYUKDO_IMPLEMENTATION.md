# ORYUKDO Gen2 implementation

을숙도 Gen2를 기반으로 분기예측 교체, 정확한 예외 복구, 윈도우 경계
인터럽트, CPU 내부 Store 전달과 외부 공개 분리를 추가한다.
기존 `eulsukdo_scheduler`는 비교용으로 보존하고 새 통합 최상위 모듈은
`gen2/src/RTL/oryukdo_scheduler.sv`를 사용한다.

## 구성

| 모듈 | 역할 |
| --- | --- |
| `oryukdo_scheduler` | 순서 있는 디코드 입력, 예측, EX/AGU/WBC 연결 |
| `oryukdo_new_entry_logic` (`U_NEL`) | 복구 가능한 매핑부 연결, IST 전달 버퍼, 대기 중 WBC Ready 갱신 |
| `oryukdo_completion_queue` | 완료 입력별 2칸 FIFO, 슬롯 짝수·홀수별 round-robin 선택과 출력 레지스터 |
| `oryukdo_result_selector` | EX 결과 token의 병렬 중복 비교, 수락 가능한 가장 앞 채널 선택 |
| `oryukdo_frontier` | 직접 인덱스 완료 추적, 윈도우 검사, 순차 확정, trap/redirect |
| `oryukdo_rename` | 추측/확정 매핑, FIFO 물리 레지스터 할당, 복구 시 free list 재구성 |
| `oryukdo_dependency_mapper` | 대기 요청 전처리·예약·기록, 완료 통지, 외부 할당기 연결 |
| `instruction_state_table`, `ready_station` | 기존 Gen2 IST 및 입력 채널별 FIFO RS 재사용 |
| `oryukdo_memory` | 내부 메모리 순서, 한 엔트리씩 Store 검색, 바이트 전달, 외부 버스 직렬화 |

기본값은 2 decode / 5 EX lanes, 128 tracking entries, 물리 레지스터 64개,
윈도우당 최대 16명령, 32비트 generation/epoch다. 외부 데이터 레지스터 파일에
쓰는 허가는 `o_wb_valid`를 사용한다. `o_result_accept`만으로는 fault 결과를
레지스터에 써도 된다는 뜻이 아니다.
`i_reset_pc`는 리셋 해제 후 첫 상승 에지에서 샘플링한다. 해당 에지까지 값을
안정적으로 유지해야 한다. 제어·유효 상태는 리셋하고, 유효 비트로 보호되는
명령 정보와 완료 FIFO 데이터 저장부는 리셋하지 않는다.
물리 레지스터 0은 항상 0을 읽도록 외부 레지스터 파일에서 보장한다. 최초 리셋 시
모든 architectural register의 매핑은 0이며, 다른 초기 레지스터 값이 필요한 플랫폼은
별도의 초기화 절차가 필요하다.

구성 조건은 `PHY >= ARCH + DECODE`, `ENTRIES >= DECODE`다. 슬롯이나 물리
레지스터가 부족하면 부분 윈도우를 조기에 닫아서 자원 반환과 입력 사이의
순환 대기를 막는다. 이 경우에도 앞선 윈도우를 건너뛰어 확정하지 않는다.
디코드 입력은 PC 검사·예측 결과를 입력 버퍼에 저장한 뒤, 다음 단계에서
자원을 확인하고 rename/token을 할당하여 NEL 전달 버퍼에 넣는다. 이어서 IST로
전달한다. `o_decode_get`은 첫 입력 버퍼의 접수이며, 슬롯이나 물리 레지스터
할당 완료를 뜻하지 않는다. 정체가 없으면 접수 에지의 1사이클 뒤 할당하고,
2사이클 뒤 IST에 전달한다. 입력 버퍼는 한 묶음이며 같은 에지에 비우고 다시
채우지 않는다. 정상 상태에서 최대 두 사이클마다 한 묶음을 받는다.
윈도우 검사와 확정은 각각 한 명령/사이클이다.
명목상 decode/issue 폭이 그대로 최대 IPC를 뜻하지는 않는다.

EX 명령의 하위 비트부터 `PC, token, flow, path, micro-op, immediate, physical rd,
physical rs1, physical rs2`가 들어간다. `token`은 하위 slot index와 상위 generation이다.
EX는 발행 시 받은 token을 결과에 그대로 반환해야 한다. 실제 PC를 token 대신
완료 식별자로 사용하면 안 된다. AGU 결과도 같은 token을 반환한다.
일반 명령의 발행 허가는 RS valid와 backend 동작 상태로 결정하며, RS는 EX 수락
시 한 번만 pop한다. 발행 시 generation을 다시 검사하지 않는다. IST에서 RS로
명령의 소유권을 한 번만 넘기고, 복구 시 IST/PRM/RS를 함께 비우는 조건에 의존한다.
결과 반환 시의 generation·발행 여부·중복 검사는 유지한다. EX가 막히면 출력
명령을 유지하며, flush는 수락 전 명령도 취소하므로 EX는 flush를 따라야 한다.

일반 EX는 `i_result_*`, 메모리 EX는 MMU 검사를 마친 `i_agu_*`로 완료를 전달한다.
메모리 명령을 양쪽으로 중복 완료시키지 않는다. `i_agu_nonspec`은 실제 버스
접근 전 판정되어야 한다. Load 반환 데이터는 정렬된 버스 워드이고 `o_wb_uop`을
함께 제공하므로, byte/halfword 추출·부호 확장이 필요한 ISA는 외부 writeback
어댑터에서 micro-op과 AGU에서 보관한 바이트 위치에 맞춰 처리해야 한다.
AGU 주소는 버스 워드에 정렬하고 byte mask로 접근 바이트를 표현한다.
AGU 오류도 엔트리의 오류 상태로 저장하고, 메모리 처리기의 등록된 완료 출력을
거쳐 완료 FIFO로 전달한다. AGU 오류 접수 에지에 `fault_pending`을 설정하여
다음 사이클부터 새 명령 입력과 할당을 막는다. 최종 오류 완료는 선행 메모리
처리 때문에 늦어질 수 있으며, trap은 선행 명령의 정확한 확정 순서를 따른다.
AGU 오류 접수는 완료 FIFO의 빈자리나 같은 사이클의 다른 메모리 완료 접수와
직접 연결되지 않는다. 일반 EX 경로는 비메모리 token만, 메모리 완료 경로는
메모리 token만 수락하며, 일반 EX 채널 사이의 중복 완료 검사는 유지한다.

EX 결과는 발행 다음 사이클부터 수락한다. 결과 생산자는 수락될 때까지
valid와 결과를 유지해야 한다. AGU도 valid/ready로 전달한다. flush로 취소된 EX
결과는 생산자에서도 폐기해야 한다. 늦게 도착한 취소 결과에는 accept를 주지 않는다.
`o_result_accept`는 완료 FIFO 접수이며, 실제 레지스터 쓰기와 Ready 통지는
뱅크에서 결과를 검증·처리할 때 발생한다. `o_wb_*`의 0/1번 채널은 완료 뱅크에
해당하고 나머지 채널의 valid는 0이다. EX 채널과 WB 채널 번호가 같다고 가정하면
안 되며, `o_wb_phy`와 `o_wb_uop`으로 결과를 연결한다. 예측기 갱신은 처리 시점에
원래 EX 채널 번호로 전달한다.
완료 접수 후 FIFO head 선택과 뱅크 출력 레지스터를 거치므로, WBC가 소비되는
상승 에지는 접수 에지보다 최소 2사이클 늦다. 이는 외부 RF 쓰기 시점이며,
NEL/PRM의 내부 Ready 소비는 등록된 통지를 사용하여 RF 쓰기보다 1사이클 늦다.
충돌 시 더 늦어지며, 외부에서는
접수 시점이 아닌 `o_wb_valid`를 기준으로 준비 완료를 판단해야 한다.
CSR 실행기는 확정 순서에 따른 EX 허가를 받은 후에만 부작용을 일으키며,
동기 예외가 있는 CSR 연산은 부작용 전에 오류를 판단해야 한다.
CSR 명령은 별도 단일 보관 버퍼에서 기다리고 순서가 되었을 때 EX로 보낸다.
RS 출력에서 CSR을 대기시키지 않으므로, 늦게 준비된 선행 명령이 같은
RS FIFO 뒤에서 막히는 교착을 피한다. CSR은 뒤 명령의 입력도 확정까지 막는다.
CSR이 확정되면 fetch epoch를 갱신하여 주소 변환이나 실행 모드 변경 전에
가져온 응답을 폐기한다. frontend는 `o_flush`뿐 아니라 epoch 변경도 따라야 한다.
외부 CSR/system 실행기는 주소 변환·권한·캐시 유지보수 등 해당 명령의 작업을
끝낸 후 완료를 반환해야 한다. 이 경로를 FENCE/FENCE.I 등의 직렬화에 사용할
경우에도 실제 캐시 유지보수와 플랫폼별 버스 완료 의미는 외부에서 구현한다.
AMO/LR·SC 원자성, 캐시 일관성 프로토콜과 MMU 자체는 이 메모리 버스의 기능이 아니다.

복구 시 IST/PRM/RS의 대기 상태를 비우고 확정 매핑을 복원한다. free list는
물리 레지스터당 한 사이클에 걸쳐 재구성한다. 이 초기 구현은 복구 시간을
줄이기 위한 분기별 체크포인트를 두지 않는다.

Base: EULSUKDO `9b0e1c6`. The EULSUKDO top remains a regression reference;
`oryukdo_scheduler` is the new decoded-instruction integration top.

## Contract

- Static fall-through prediction by default. External mode elaborates only the
  external predictor connection; a missing prediction stalls control admission.
- Completion identities contain a direct slot index and generation. Old results
  cannot write a reused physical register. EX must honor the result accept mask.
- Execution is speculative; architectural retirement is ordered. A sequential
  frontier examines the oldest window before publishing its stores. Fault stops
  are registered, so admission may overlap the edge that captures a fault. The
  younger work remains speculative and is discarded; trap delivery waits for
  the older prefix. This removes the completion-to-admission combinational path.
- Stores become internally complete after address, data and MMU checks. Younger
  loads use the youngest preceding store per byte. External writes wait for
  authorization. A failed branch discards only the younger work.
- CSR instructions end a window, execute at the ordered head, and block younger
  admission through retirement. Retirement advances the fetch epoch, including
  when there is no redirect pulse. MMU-designated
  non-speculative accesses insert a serialization boundary before themselves.
  These boundaries are necessary to avoid store/MMIO/CSR circular waits. Faults
  also permit the correct prefix of a window to retire before entering the trap.
- Interrupts are sampled at confirmed window boundaries (and an idle frontier),
  including immediately after a serialized CSR. The external CSR unit supplies
  the current eligible/pending condition and trap vector. Pending interrupts stop
  new admission and seal a partial window; they do not require a new fetch response.
  External memory must eventually respond (or report a fault). No fixed interrupt
  latency is promised for an indefinitely stalled external operation. On trap,
  the external CSR unit must update interrupt eligibility to prevent repeated entry.
- MMU and CSR implementations, execution units, data register file and instruction
  fetch/decode are integration components. MMU must finish access checks before
  submitting an AGU result. Side-effecting reads and writes must be marked
  non-speculative. Aligned bus-word addresses plus byte masks describe memory
  transactions; splitting misaligned requests is outside this scheduler.
- The decoded input is a contiguous valid prefix in program order from the
  supplied fetch PC/epoch. A
  control instruction terminates the accepted prefix. Fetch must discard its
  younger bundle suffix and follow the prediction/redirect. Recovery invalidates
  outstanding fetch responses by epoch.
- Decode acknowledgement captures the validated bundle and its prediction in
  a one-bundle register; allocation occurs later. Fetch PC advances at capture.
  Held operands are renamed only on allocation, using current readiness/WBC.
  Window/flow assignment also uses current allocation state, so resource-pressure
  sealing cannot leave stale flow IDs in the buffer. Flush drops the buffer;
  an interrupt before allocation resumes at the frontier's confirmed PC.
- Window publication is ordered, not atomic publication of all stores at once.
  Memory requests remain stable until accepted; responses are in order with one
  transaction outstanding. A store response acknowledges irreversible completion.
  A precise store error must mean that the failed operation made no partial
  externally visible write; buses with partial effects need a platform error policy.
- Generation/epoch counters must not wrap while an old external response remains
  possible. Reset also requires external agents to discard old transactions.

## Implementation and validation status

### PRM 행 용량 확인과 기록 단계 분리

`U_PRM_MAPPING_COUNTER → input_map_fit → input_fire → U_PRM_IST_MAP/CE`
경로를 끊기 위해 전처리 다음에 작은 예약 레지스터를 추가했다. 전처리는 기존처럼
중복 요청을 제거하고 같은 물리 레지스터를 기다리는 선행 요청 수를 센다.
예약 단계는 현재 Ready와 행 사용량을 읽어 각 요청의 기록 위치, 행의 최종 개수,
Ready 우회 여부를 저장한다. 기록 단계는 저장한 계획만 적용한다.

큰 요청 데이터는 기존 `map_data`에 그대로 유지하므로 별도 명령 FIFO를 복제하지
않는다. 2d5i·행 깊이 4 기준 추가 논리 상태는 유효 1, Ready 4, 슬롯 쓰기 허용 16,
카운터 쓰기 허용 4, 새 카운터 값 12로 총 37비트다. 실제 합성 FF 증감과는 다를 수
있다. 기록과 다음 요청 전처리는 같은 에지에 가능하지만, 예약과 기록은 서로 다른
에지다. 정체가 없을 때 최대 두 사이클마다 한 묶음을 처리한다. 기존 디코드 접수도
최대 두 사이클마다 한 묶음이지만, 대기열 버스트를 해소하는 속도는 별도 제한이다.

예약 중에는 행 drain을 잠시 막아 계산해 둔 사용량이 바뀌지 않게 한다. 행별 충돌
검색이나 잠금 테이블을 추가하지 않는 보수적 방식이다. 예약을 잡는 에지의 drain은
이미 Ready인 행이고, 새 기록 대상은 아직 Ready가 아닌 행이므로 충돌하지 않는다.
Ready 우회가 포함된 계획은 통지 레지스터가 비었을 때 기록한다. 출력 FIFO의 즉시
ready 신호를 쓰기 허용까지 연결하지 않는다. 이미 잡힌 통지 묶음은 계속 출력하므로
통지 정체가 풀리면 예약도 진행한다.

예약 직후 또는 정체 중 WBC가 와도 예약 내용을 다시 분류하지 않는다. Ready 비트는
계속 기록하고, 먼저 저장한 계획대로 대기 명령을 추가한 뒤 그 행 전체를 깨운다.
기존 대기 명령과 새 대기 명령이 모두 한 번씩 통지된다. reset/복구는 계획 유효 비트와
기존 큐 상태를 함께 지워 취소된 요청이 나중에 기록되지 않게 한다.

통합 회귀는 17개 구성에서 통과했다. 새 PRM 단독 검사는 decode 1/2/3, 행 깊이
2/4/3, 입력 버퍼 깊이 3/3/2에서 WBC 시점 이동, 중복 피연산자, 행 포화,
앞 묶음 정체, 통지 버퍼 정체, 기존 행에 예약하면서 완료, 예약 중 초기화를 검사한다.
예약 동안 행의 카운터가 바뀌지 않음과 예약/배출 충돌 없음도 assertion으로 검사한다.

32엔트리·2d5i·PHY64·RS128·generation/epoch 32비트, Vivado 2022.2,
`xc7z020clg400-1`에서 70MHz로 합성·배치·배선했다. 이전과 동일하게 완료된
배선에 `phys_opt_design -directive AggressiveExplore` 및
`route_design -directive Explore`를 적용했다. RTL 변경은 PRM 모듈 하나다.

| 항목 | 이전 최종 회로 | 예약 단계·기본 배선 | 예약 단계·물리 최적화 후 |
| --- | ---: | ---: | ---: |
| LUT | 43,525 | 43,317 | 43,319 |
| FF | 23,569 | 23,614 | 23,614 |
| BRAM36 | 42 | 42 | 42 |
| 최장 데이터 경로 | 13.933ns / 15단 | 14.674ns / 15단 | 13.932ns / 10단 |
| 70MHz setup slack | -0.008ns | -0.359ns | +0.057ns |
| 고정 배선 STA 통과 경계 | 69.9MHz | 68.2MHz | 70.2MHz |

같은 기본 배선 단계끼리 비교하면 이전 64.3MHz에서 68.2MHz로 개선됐다.
물리 최적화까지 적용한 최종 비교에서는 LUT 206개 감소, FF 45개 증가이며,
클럭 경계는 0.3MHz 상승했다. PRM 병목은 끊었지만 전체 클럭 상승은 작다.
계획 레지스터 37개와 전체 FF 순증 45개는 구분한다. 후자는 다른 합성 최적화
결과의 차이도 포함한다.

최종 netlist의 PRM 카운터 FF 192개에서 매핑 테이블 FF 1,280개로 향하는
조합 fanout 및 타이밍 경로는 모두 0개다. 계획 레지스터는 37개로 확인됐다.
기존 decode, 메모리 완료, RS 발행, 내부 Ready 파이프라인 분리 검사도 통과했다.
기본 합성 netlist와 최종 물리 최적화 netlist가 모두 공개 인터페이스 기능 검사를
통과했으며, 이전 최종 netlist에도 같은 테스트벤치를 다시 실행했다.

| 동일 테스트벤치의 명령 32개 처리 | 이전 최종 회로 | 변경 후 최종 회로 |
| --- | ---: | ---: |
| 서로 독립적인 명령 | 91사이클 | 91사이클 |
| 앞 명령 결과에 의존하는 연쇄 | 553사이클 | 555사이클 |

이 값은 테스트벤치가 EX 결과를 반환하고 주기적으로 EX 출력을 막는 제한된
시나리오다. 완성 CPU의 IPC나 응용 프로그램 성능을 뜻하지 않는다. PRM 처리율
감소와 drain 일시 중단의 영향이 모든 워크로드에서 이 정도라는 보장도 아니다.

| 최종 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 65MHz | +1.156ns | +0.060ns | 통과 |
| 70MHz | +0.057ns | +0.060ns | 통과 |
| 70.2MHz | +0.016ns | +0.060ns | 통과 |
| 70.3MHz | -0.004ns | +0.060ns | 실패 |

70MHz는 그 제약으로 구현한 회로의 통과 결과다. 70.2MHz는 동일 배선에서
클럭 제약만 바꾼 STA 경계이며, 별도 70.2MHz 구현이나 실기 클럭 검증은 아니다.
판정은 setup/hold/pulse-width를 포함한다. 통과 경계의 여유는 작고, 65MHz에서는
setup 여유가 1.156ns다. OOC 스케줄러만 포함하므로 보드 I/O 제약, 외부 EX/RF
왕복 경로, 완성 CPU, bitstream 및 실기 측정은 별도다.

최종 최장 경로는 `U_FRONTIER/head_reg[0]_rep__1/C`에서
`U_NEL/U_RENAME/free_queue_reg[39][4]/CE`까지다. 선두 명령의 목적 architectural
register를 골라 이전 확정 물리 레지스터를 읽고, 반환 가능한지 검사한 뒤 free queue의
쓰기를 허용하는 경로다. 10단, 데이터 지연 13.932ns 중 논리 2.255ns·배선
11.677ns(83.8%)다. 다음 개선 후보는 이 반환 판단과 free queue 기록 사이의 분리다.

52,916개 routable net이 모두 연결됐고 배선 오류는 0개다. latch, black box,
조합 loop, clock 없는 내부 FF 및 제약 없는 내부 끝점도 0개다. DRC error/critical
warning은 없지만, 기존 RAM 비동기 제어·부하 없는 net·OOC PS7 관련 경고는 남는다.

[최종 소스 해시·회귀·경로·자원·클럭·사이클 비교 기록](docs/validation/oryukdo_gen2.json),
[이번 기본 배선 기록](docs/validation/oryukdo_gen2_prm_before_physopt.json),
[변경 전 최종 기록](docs/validation/oryukdo_gen2_before_prm_reservation.json).
구현 디렉토리는 `gen2/build/oryukdo_prm_reservation32_70mhz`와
`gen2/build/oryukdo_prm_reservation32_70mhz_physopt`다. 이전 netlist 재검사는
`gen2/build/oryukdo_prm_reservation_baseline_gate`에 보존했다.

### 완료 입력 중복 비교 병렬화 — 이전 측정

EX 결과 입력의 `queue_valid[앞 채널]` 판정을 뒤 채널이 다시 참조하던 연쇄를
제거했다. `oryukdo_result_selector`는 각 채널보다 앞선 모든 채널에 대해
valid·FIFO ready·전체 token 일치를 독립적으로 비교하고 OR reduction으로
중복 여부를 정한다. 선택 뒤에는 해당 채널 자신의 token 유효성만 적용한다.
추가 FIFO·파이프라인 단계는 없고 완료 접수, WBC, 내부 Ready 지연도 유지한다.

token 유효성은 slot/generation 및 해당 명령의 live·issued·queued·memory 상태로
결정되므로 같은 token의 유효성은 채널에 관계없이 같다. 따라서 현재 token이
유효하다면 앞의 같은 token도 유효하며, 앞 채널의 최종 접수 판정을 기다릴 필요가
없다. 앞쪽 FIFO가 full이면 뒤의 ready 채널을 막지 않는다. 같은 token을 여러
ready 채널이 제시하면 번호가 가장 낮은 채널만 수락한다. 메모리 완료와 일반
EX 완료의 분리, stale token 거부, 이미 FIFO에 접수된 결과의 재접수 거부는 유지한다.
향후 채널별 별도 유효 조건을 추가할 경우 이 동등성 조건을 다시 검토해야 한다.

3·5·7채널 선택부 테스트는 8가지 token 배치에 대해 모든 valid/ready 조합을
검사하고, 4,096개 무작위 입력도 추가한다. 각 입력은 3가지 token 기반 유효성
모델로 기존 직렬 루프와 비교한다. 총 비교 횟수는 456,192회이며, blocked 앞
채널·여러 중복 그룹·상위 generation만 다른 token을 포함한다. 통합 테스트는
각 채널이 승자가 되는 경우의 데이터와 fault 선택, 다음 사이클 재접수 거부,
같은 slot의 오래된 generation이 정상 결과를 억제하지 않는 경우를 검사한다.
동일 token의 채널별 유효성 일치 및 중복 접수 없음도 RTL assertion으로 확인한다.

RTL 14개 구성과 기본 배선 회로의 합성 netlist 기능 검사가 통과했다.
물리 최적화 후 최종 회로도 동일한 외부 인터페이스 테스트를 통과했다.
기본값 128엔트리는 RTL 기능 검증 범위이며, 아래 수치는 32엔트리·2d5i·PHY64·
RS128·generation/epoch 32비트, Vivado 2022.2, Zynq-7020의 스케줄러 단독 OOC다.

| 항목 | 직전 RTL·기본 배선 | 병렬화·기본 배선 | 병렬화·물리 최적화 후 |
| --- | ---: | ---: | ---: |
| LUT | 43,900 | 43,451 | 43,525 |
| FF | 23,567 | 23,569 | 23,569 |
| BRAM36 | 42 | 42 | 42 |
| 최장 데이터 경로 | 15.258ns / 18단 | 15.411ns / 19단 | 13.933ns / 15단 |
| 70MHz setup slack | -1.127ns | -1.266ns | -0.008ns |
| 고정 배선 STA 통과 경계 | 64.8MHz | 64.3MHz | 69.9MHz |

병렬화만으로는 LUT가 449개 줄었으나 다른 경로가 병목이 되어 기본 배선의
클럭은 소폭 하락했다. 같은 RTL의 완료된 70MHz checkpoint에
`phys_opt_design -directive AggressiveExplore`와 `route_design -directive Explore`를
추가 적용하여 최종 결과를 얻었다. 최종 LUT는 직전보다 375개(-0.85%) 적고,
통과 경계는 7.9% 높다. 이 클럭 개선 전체를 병렬화 RTL만의 효과로 해석하면 안 된다.
새 파이프라인 상태는 없으며, FF 2개 순증은 합성 최적화 결과의 차이다.
70MHz는 0.008ns 부족하므로 통과로 반올림하지 않는다.

| 최종 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 65MHz | +1.091ns | +0.031ns | 통과 |
| 69.9MHz | +0.012ns | +0.031ns | 통과 |
| 70MHz | -0.008ns | +0.031ns | 실패 |

모든 구현 단계는 70MHz 제약을 사용했고, 위 경계 측정은 최종 배선에 대해
클럭 제약만 바꾼 STA다. 통과 판정에는 setup/hold/pulse-width를 포함한다.
69.9MHz 경계값의 여유는 작다. 보드 I/O 지연, 외부 EX/RF와의 왕복 경로,
완성 CPU, bitstream 및 실기 측정은 포함하지 않으므로 보드 동작 클럭을 뜻하지 않는다.

최종 경로는 `U_PRM/U_PRM_MAPPING_COUNTER/reg_mem_reg[53][2]`에서
`U_PRM/GEN_PRM_IST_MAP[2].U_PRM_IST_MAP/reg_mem_reg[51][4].CE`까지다.
물리 레지스터별 대기 명령 수 읽기 → 새 대기 묶음의 저장 공간 검사 → 통지 버퍼
수락 여부 반영 → 대기 명령 매핑 쓰기 허용으로 이어진다. 13.933ns 중 논리는
2.378ns, 배선은 11.555ns다. 결과 입력의 직렬 중복 판정은 더 이상 최장 경로가 아니다.

최종 배선에서 기존 Ready, RS 발행, AGU 완료, decode 경로 단절 검사도 모두
통과했다. 51,624개 routable net 전부 배선됐고 routing error는 0개다.
래치·블랙박스·조합 루프·클럭 없는 내부 경로는 0개다. RAM 비동기 제어,
routable load 없는 net, OOC PS7 부재에 관한 기존 DRC 경고는 남아 있다.

[당시 소스 해시·기능·자원·타이밍 검증 기록](docs/validation/oryukdo_gen2_before_prm_reservation.json)
및 [같은 RTL의 물리 최적화 전 기록](docs/validation/oryukdo_gen2_parallel_before_physopt.json).

- 기본 FPGA 빌드: `gen2/build/oryukdo_parallel_completion32_70mhz_r2`
- 최종 FPGA 빌드: `gen2/build/oryukdo_parallel_completion32_70mhz_physopt`
- RTL 회귀 검사: `gen2/build/oryukdo_parallel_completion_regression`
- 각 빌드의 기능 검사: `gate_sim/result.json`
- 통과 클럭 checkpoint와 제약: 최종 빌드의 `sweep/`
- 최초 `_r2` 없는 실행은 Vivado 내부 unimacro 라이브러리 로딩 오류로 시작 단계에서
  종료됐다. 동일 RTL로 재실행한 `_r2`가 기본 비교 결과다.

추가 물리 최적화 재현 명령(출력 디렉토리는 새 경로 사용):

```powershell
python gen2/src/TB/run_oryukdo_postroute.py --build gen2/build/oryukdo_parallel_completion32_70mhz_r2 --output gen2/build/oryukdo_parallel_completion32_70mhz_physopt_repro
python gen2/src/TB/run_oryukdo_netlist.py --build gen2/build/oryukdo_parallel_completion32_70mhz_physopt_repro
```

스크립트는 부모 소스 snapshot과 합성·배치 보고서를 보존하고, 부모 routed
checkpoint 해시 및 적용 directive를 manifest에 기록한다. 기능 검사는 최종
물리 최적화 netlist에 대해 다시 실행해야 한다. 재현 스크립트는 배선 보수 전
`scheduler_physopt.dcp`도 추가 보존하며, 이번 실행의 최종 결과는 `scheduler_routed.dcp`다.

### 내부 Ready 통지 파이프라인 — 직전 비교 기준

완료 token 검증과 NEL/PRM의 Ready 처리를 분리했다. 외부 `o_wb_*`의 RF 쓰기
타이밍은 유지하고, 두 완료 뱅크의 valid와 물리 레지스터 번호만 한 단계 등록한다.
NEL의 rename/전달 버퍼와 PRM이 동일한 등록된 통지를 받아, 검증된 완료에서
Ready 갱신과 PRM 대기 등록까지의 긴 조합 경로를 끊는다. 데이터·micro-op·token
전체를 저장하는 새 FIFO는 없으며, PHY64에서 논리적으로 14비트의 상태를 추가한다.

RF를 먼저 쓴 뒤 다음 에지에 Ready가 소비되므로 데이터보다 일찍 실행 허가를
주지 않는다. PRM은 Ready를 물리 레지스터 수명 동안 유지하여 통지 뒤에 등록된
대기 명령도 처리한다. NEL도 통지를 전달 버퍼에 누적하며 IST 전달 에지에 우회한다.
이미 준비된 명령의 경로는 그대로이고, Ready 통지 자체는 1사이클 늦어진다.
의존 명령의 실제 발행 지연은 IST/PRM 경로 선택과 큐 정체에 따라 더 커질 수
있으므로, 클럭 상승이 그대로 IPC 또는 프로그램 성능 상승을 뜻하지는 않는다.

flush/초기화 중에는 통지를 막고 valid를 비운다. 완료 직후에는 해당 명령의
확정·물리 레지스터 재사용이 아직 불가능하다는 조건을 이용하며, 시뮬레이션에서
지연된 통지의 token이 여전히 live인지, 새 물리 레지스터 할당과 겹치지 않는지
검사한다. 두 피연산자 완료와 입력의 8가지 시점 조합, 복구와 후행 완료의 8가지
시점 조합, 기존 정체·슬롯 및 물리 레지스터 재사용 검사를 포함한다.

동일한 32엔트리·2d5i·PHY64·RS128·generation/epoch 32비트·70MHz 제약으로
Vivado 2022.2 합성·배치·배선을 완료했다. RTL 11개 구성과 합성 netlist의 기능
검사가 통과했다. 기본 128엔트리는 RTL 검증 범위이며, 아래 물리 구현 결과는
32엔트리 구성의 스케줄러 단독 OOC다.

| 배치·배선 후 항목 | 직전 버전 | Ready 통지 등록 |
| --- | ---: | ---: |
| LUT | 43,743 | 43,900 (+157, 약 0.36%) |
| FF | 23,559 | 23,567 (+8) |
| BRAM36 | 42 | 42 |
| 최장 데이터 경로 | 15.760ns / 17단 | 15.258ns / 18단 |
| 70MHz setup slack | -1.776ns | -1.127ns |
| 70MHz setup 위반 endpoint | 6,298 | 119 |
| 고정 배선 STA 통과 경계 | 62.2MHz | 64.8MHz (+4.2%) |

Ready 파이프라인은 실제로 14개 FF로 구현됐다. 다른 부분의 최적화를 포함한
전체 FF 순증은 8개다. 최적화 직후 LUT는 43,611에서 43,781로 늘었고,
배치·배선 후에는 위 표의 43,900개가 됐다. 70MHz 목표는 아직 실패다.

| 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 60MHz | +1.254ns | +0.058ns | 통과 |
| 64.8MHz | +0.019ns | +0.058ns | 통과 |
| 64.9MHz | -0.005ns | +0.058ns | 실패 |
| 70MHz | -1.127ns | +0.058ns | 실패 |

각 통과 판정은 setup/hold/pulse-width를 포함한다. 70MHz로 합성·배치·배선한
결과를 고정하고 클럭 제약만 바꾼 STA이며, 60/64.8MHz로 처음부터 다시 구현한
결과나 보드 실측이 아니다. 경계값은 여유가 작고 60MHz에서는 1.254ns다.
보드 IO 제약, 완성 CPU, bitstream, 실기 동작 및 프로그램 IPC 측정은 포함하지 않는다.

최종 checkpoint에서 frontier generation 레지스터 1,024개와 PRM 입력 버퍼
순차 셀 114개 사이의 timing path 및 조합 fanout endpoint가 모두 **0개**임을
확인했다. Ready 레지스터 14개도 존재한다. 기존 metadata → RS, fetch PC →
메모리 generation, AGU → memory processed 경로 단절 검사도 모두 통과했다.
51,852개 routable net 전부 배선됐고 routing error는 0개다. 래치·블랙박스·
조합 루프·클럭 없는 내부 경로도 0개다. 기존 RAM 비동기 제어, routable load 없는
net, OOC의 PS7 부재 관련 DRC 경고는 유지되며 DRC 무경고를 뜻하지 않는다.

현재 최장 경로는 `metadata[5].generation[25]`에서 `metadata[21].queued`까지다.
반환 token 검증 → 먼저 온 채널과의 중복 완료 비교 → 뒤 채널의 접수 허가 →
해당 명령의 완료 FIFO 접수 표시를 한 사이클에 갱신한다. 앞 채널의 판정이 뒤
채널의 중복 판정에 연쇄적으로 반영되는 구조가 다음 개선 대상이다.
15.258ns 중 논리는 3.582ns, 배선은 11.676ns다.

[완료 비교 병렬화 전 소스 해시·기능·자원·타이밍 검증 기록](docs/validation/oryukdo_gen2_before_parallel_completion.json)

- FPGA 빌드: `gen2/build/oryukdo_wakeup_pipeline32_70mhz`
- RTL 회귀 검사: `gen2/build/oryukdo_wakeup_pipeline_regression`
- 합성 후 기능 검사: FPGA 빌드의 `gate_sim/result.json`
- Ready 경로 단절 검사: FPGA 빌드의 `wakeup_audit.txt`
- 검사 스크립트: `gen2/src/TB/audit_oryukdo_wakeup.tcl`
- 통과 클럭 checkpoint와 제약: FPGA 빌드의 `sweep/`

### RS 발행 제어 단순화 — 직전 비교 기준

발행 시 metadata의 generation·valid·issued를 다시 읽어 EX valid와 RS pop을
결정하던 경로를 제거했다. 일반 RS pop은 backend 동작 상태, RS valid, EX 수락
신호만으로 결정한다. 명령 종류(memory/store/CSR) 출력에는 metadata 조회가
남아 있지만 RS pop을 제어하지 않는다. 새 EX FIFO나 파이프라인 지연은 추가하지 않았다.

IST는 RS에 넘긴 명령을 다시 넘기지 않고, RS는 출력에서 EX가 수락할 때까지
소유한다. 아직 발행하지 않은 명령은 완료·확정될 수 없어 슬롯도 재사용되지 않는다.
복구 시 IST/PRM/RS를 함께 초기화하고, 매핑 복원 중에는 backend를 정지한다.
CSR은 선행 명령이 모두 확정된 head에서만 발행하고 후행 명령의 할당을 막으므로
그 시점에 RS는 비어 있다. 이 조건에 따라 CSR의 head token 비교도 RS pop에서 분리했다.

시뮬레이션 assertion으로 모든 RS 출력의 live token, 미발행·미완료 상태,
출력 간 token 중복 없음, ordered CSR과 RS의 동시 점유 없음을 검사한다.
외부 테스트에서는 장시간·채널별 EX backpressure, WBC 후 대기 명령 발행,
발행 전 완료 거부, flush와 EX 수락 재개가 겹치는 경우, 취소 슬롯 재사용 후
옛 결과 거부, CSR 출력 유지 등을 검사한다. 이는 회귀 검증이며 형식 증명은 아니다.

동일한 32엔트리·2d5i·PHY64·RS128·generation/epoch 32비트·70MHz 제약으로
Vivado 2022.2 합성·배치·배선을 완료했다. RTL 11개 구성과 합성 netlist 기능
검사를 모두 통과했다. 기본 128엔트리는 RTL 검증 범위이고 아래 물리 구현 수치는
32엔트리 구성이다.

| 배치·배선 후 항목 | 직전 버전 | RS 발행 단순화 |
| --- | ---: | ---: |
| LUT | 46,041 | 43,743 (-2,298, 약 5.0%) |
| FF | 23,595 | 23,559 |
| BRAM36 | 42 | 42 |
| 최장 데이터 경로 | 15.492ns / 15단 | 15.760ns / 17단 |
| 70MHz setup slack | -1.741ns | -1.776ns |
| 고정 배선 STA 통과 경계 | 62.3MHz | 62.2MHz |

최적화 직후 LUT도 45,565에서 43,611로 줄었다. 목표로 한 발행 경로는 제거됐지만,
다른 완료 처리 경로가 최장 경로가 되어 전체 클럭은 개선되지 않았다. 이번 변경의
확인된 이득은 자원 감소이며, 70MHz 목표는 여전히 실패다.

최장 경로는 `U_FRONTIER/G_ROW[6].generations_reg[6][1]`에서
`U_PRM/U_PRM_INPUT_BUFFER/reg_mem_reg[0][40].CE`로 이어진다.
완료 token의 generation 확인 → 완료 수락과 WBC 유효 판정 → NEL 전달 명령의
operand Ready 갱신 → IST의 PRM 대기 등록 결정 → PRM 입력 버퍼 쓰기 허용을
한 사이클에 처리한다. 15.760ns 중 논리는 3.541ns, 배선은 12.219ns다.
다음 클럭 개선 대상은 이 완료 검증과 Ready 전달 사이의 조합 연결이다.

| 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 55MHz | +2.120ns | +0.044ns | 통과 |
| 62.2MHz | +0.015ns | +0.044ns | 통과 |
| 62.3MHz | -0.011ns | +0.044ns | 실패 |
| 70MHz | -1.776ns | +0.044ns | 실패 |

이는 70MHz로 구현한 회로의 배선을 고정하고 클럭 제약만 변경한 STA이며,
각 클럭으로 재합성·재배치한 결과나 보드 실측이 아니다. 통과 판정은
setup/hold/pulse-width를 포함한다. 경계값의 여유는 작고 55MHz에서는 2.120ns다.
51,775개 routable net을 모두 배선했고 routing error는 0개다. 래치·블랙박스·
조합 루프·클럭 없는 내부 경로도 0개다. RAM 비동기 제어, routable load 없는 net,
OOC의 PS7 부재에 관한 DRC 경고는 남아 있으므로 DRC 무경고나 보드 검증을 뜻하지 않는다.

최종 checkpoint에서 metadata generation/issued 레지스터 1,056개와 RS 순차
셀 3,686개 사이의 timing path 및 조합 fanout endpoint는 모두 **0개**다.
같은 검사 스크립트를 직전 회로에 적용하면 경로가 검출되고 조합 endpoint는
4,565개이므로, 검사 대상 누락으로 통과한 것이 아님도 확인했다.
기존 fetch-PC → 메모리 generation 및 AGU → memory processed 경로 단절 검사도 통과했다.

[Ready 파이프라인 전 소스 해시·기능·자원·타이밍 검증 기록](docs/validation/oryukdo_gen2_before_wakeup_pipeline.json)

- FPGA 빌드: `gen2/build/oryukdo_issue_simplification32_70mhz`
- RTL 회귀 검사: `gen2/build/oryukdo_issue_simplification_regression`
- 합성 후 기능 검사: FPGA 빌드의 `gate_sim/result.json`
- 발행 경로 단절 검사: FPGA 빌드의 `issue_audit.txt`
- 검사 스크립트: `gen2/src/TB/audit_oryukdo_issue.tcl`
- 통과 클럭 checkpoint와 제약: FPGA 빌드의 `sweep/`

### 메모리 완료 경로 분리 — 직전 비교 기준

AGU 오류의 직접 완료 우회 경로를 제거했다. 오류를 포함한 모든 메모리 완료가
기존 `U_MEMORY.o_complete_*` 레지스터를 거치며, 새 FIFO나 데이터 레지스터는
추가하지 않았다. 메모리 완료 ACK는 해당 token의 폐기 여부 또는 완료 FIFO의
ready로 결정하고, 현재 AGU 요청의 오류 여부로 막지 않는다.

메모리/비메모리 분류를 양쪽 완료 입력에서 명시적으로 검사하여, 두 종류 사이의
token 중복 비교를 제거했다. EX/EX 중복 비교와 generation·valid·queued 검사는
유지했다. 시뮬레이션에서는 두 종류가 같은 token을 동시에 제출하지 않는다는
불변 조건도 검사한다.

동일한 32엔트리·2d5i·70MHz 조건으로 합성·배치·배선을 완료했다. RTL 11개
구성과 Vivado 2022.2 합성 netlist 기능 검사가 통과했다. 선행 Load가 막힌 동안
faulting Load/Store가 대기하는 경우의 빠른 입력 중단, 중복 AGU와 잘못된 EX
완료 거부, 선행 MMIO 진행, 분기 복구에 따른 미완료 오류 폐기를 추가 검증했다.

| 배치·배선 후 항목 | 직전 버전 | 메모리 완료 경로 분리 |
| --- | ---: | ---: |
| LUT | 46,760 | 46,041 |
| FF | 23,581 | 23,595 |
| BRAM36 | 42 | 42 |
| 최장 데이터 경로 | 17.209ns / 22단 | 15.492ns / 15단 |
| 70MHz setup slack | -2.842ns | -1.741ns |
| 고정 배선 STA 통과 경계 | 58.3MHz | 62.3MHz (+6.9%) |

합성 최적화 후 LUT는 46,025에서 45,565로 줄었다. 최종 배선은 routable net
52,953개 전부 완료했고 routing error는 0개다. 래치·블랙박스·조합 루프·클럭 없는
내부 경로도 0개이며, 기존 RAM 비동기 제어 및 OOC 관련 DRC 경고는 보고서에 남겼다.

| 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 55MHz | +2.155ns | +0.056ns | 통과 |
| 62.3MHz | +0.024ns | +0.056ns | 통과 |
| 62.4MHz | -0.001ns | +0.056ns | 실패 |
| 70MHz | -1.741ns | +0.056ns | 실패 |

통과 판정에는 setup/hold/pulse-width를 모두 포함했다. 70MHz로 합성·배치·배선한
결과에서 클럭 제약만 변경한 **고정 배선 STA**이며, 55MHz/62.3MHz로 처음부터
재합성·재배치한 결과나 보드 실측이 아니다. 현재 수치는 스케줄러 단독 OOC의
32엔트리 구성 기준이며, 기본 128엔트리는 RTL 기능 검증 범위다.

최종 checkpoint에서 AGU 입력 포트 113개와 메모리 `processed` 레지스터 32개
사이의 조합 경로를 검사했다. timing path와 combinational fanout endpoint가
모두 **0개**다. 입력 IO delay가 없는 OOC 타이밍만으로 잘못 통과하는 경우를
피하기 위해 실제 신호 연결도 검사했다.

이 버전의 최장 경로는 `metadata[21].generation[14]`에서
`U_RS/genblk1[0].U_RS_FIFO/G_INPUT[2].U_FIFO/forward_data_reg[77].CE`로 이어진다.
EX로 보낼 RS head의 token 유효성을 확인한 뒤 `o_ex_valid`, `rs_pop`, RS 내부
FIFO의 pop/보충 및 forward 레지스터 갱신 허용으로 이어지는 경로다.
15.492ns 중 논리는 3.347ns, 배선은 12.145ns다.

[발행 단순화 전 소스 해시·기능·자원·타이밍 검증 기록](docs/validation/oryukdo_gen2_before_issue_simplification.json)

- 당시 FPGA 빌드: `gen2/build/oryukdo_memory_completion32_70mhz`
- RTL 회귀 검사: `gen2/build/oryukdo_memory_completion_regression`
- 합성 후 기능 검사: FPGA 빌드의 `gate_sim/result.json`
- 경로 단절 검사: FPGA 빌드의 `memory_completion_audit.txt`
- 검사 스크립트: `gen2/src/TB/audit_oryukdo_memory_completion.tcl`

직전 버전의 소스 해시와 검증 결과는
[메모리 완료 경로 개선 전 기록](docs/validation/oryukdo_gen2_before_memory_completion.json)에 보존했다.

### 직전 버전: PC 검사·할당 경로 파이프라인 추가

이전 배선의 최장 경로는 fetch PC 검사에서 rename 자원 확인, 슬롯 선택,
generation 증가를 거쳐 메모리 추적 테이블로 이어지는 19.825ns / 32단 경로였다.
이를 끊기 위해 검증된 명령 묶음과 예측 결과를 저장하는 입력 레지스터 단계를
추가했다. PC 후보도 `fetch_pc + lane * PC_STEP`으로 각각 계산하여, 앞 채널의
선택 결과가 다음 채널의 PC 덧셈 입력으로 이어지지 않게 했다.

동일 32엔트리·2d5i·70MHz 설정으로 합성·배치·배선을 완료했다. RTL 11개 구성과
Vivado 2022.2 합성 netlist 기능 검사가 통과했으며,
PC 불일치/분기 뒤 채널 거절, 입력 버퍼 정체 중 payload 유지와 WBC 반영,
할당 전 flush 폐기 및 인터럽트 복귀 PC 검사를 포함한다.

| 합성 최적화 후 항목 | 직전 버전 | 입력 파이프라인 추가 |
| --- | ---: | ---: |
| LUT | 46,902 | 46,025 |
| FF | 23,295 | 23,581 |
| BRAM36 | 42 | 42 |
| 70MHz setup slack | -3.285ns | -0.141ns |
| 최장 데이터 경로 | 17.438ns / 35단 | 14.048ns / 16단 |

| 배치·배선 후 항목 | 직전 버전 | 입력 파이프라인 추가 |
| --- | ---: | ---: |
| LUT | 47,656 | 46,760 |
| FF | 23,295 | 23,581 |
| BRAM36 | 42 | 42 |
| 최장 데이터 경로 | 19.825ns / 32단 | 17.209ns / 22단 |
| 70MHz setup slack | -5.840ns | -2.842ns |
| 고정 배선 STA 통과 경계 | 49.6MHz | 58.3MHz (+17.5%) |
| 여유를 둔 고정 배선 검사 클럭 | 45MHz | 55MHz |

새 배선의 55MHz setup slack은 +1.054ns, 58.3MHz는 +0.025ns이며,
두 경우 hold slack은 +0.039ns이고 setup/hold/pulse-width 검사를 모두 통과했다.
58.4MHz는 setup slack -0.005ns로 실패했다. 70MHz 목표는 아직 미달이다.
이는 70MHz로 합성·배치·배선한 결과의 클럭 제약을 바꾼 **고정 배선 STA**다.
55MHz로 처음부터 재합성·재배치한 결과나 보드 실측이 아니다.
통과 클럭의 checkpoint와 XDC는 새 빌드의 `sweep/`에 보존했다.

최종 checkpoint에서 fetch PC 레지스터 32개와 메모리 generation 레지스터
1,024개 사이의 조합 타이밍 경로가 **0개**임을 별도로 검사했다. fetch PC에서
시작하는 새 최장 경로는 13.460ns이며 70MHz에서 +0.841ns 여유가 있다.
검사 스크립트는 `gen2/src/TB/audit_oryukdo_decode_pipeline.tcl`이다.

전체 최장 경로는 이제 `U_MEMORY/entries[16].generation[5]`에서
`U_MEMORY/entries[13].processed`로 이어진다. AGU token의 유효성·generation을
검사하고, AGU fault와 기존 메모리 완료 사이의 접수 우선순위/중복 여부를
판정한 뒤 완료 FIFO 접수와 메모리 처리 상태 갱신으로 이어지는 경로다.
17.209ns 중 논리가 4.919ns, 배선이 12.290ns다.

54,225개 routable net 전부 배선되었고 routing error는 0개다. 래치·블랙박스·
조합 루프·클럭 없는 내부 경로도 0개다. RAM 비동기 제어, routable load가 없는
출력 net, OOC에서 PS7 블록이 없는 것에 대한 DRC 경고는 보고서에 보존했다.
FPGA 수치는 스케줄러 단독의 32엔트리 구성 기준이며, 기본 128엔트리는 RTL 검증 범위다.

[입력 파이프라인 단계의 소스 해시·기능·자원·타이밍 검증 기록](docs/validation/oryukdo_gen2_before_memory_completion.json)

- 현재 FPGA 빌드: `gen2/build/oryukdo_decode_pipeline32_70mhz`
- RTL 회귀 검사: `gen2/build/oryukdo_decode_pipeline_regression`
- 합성 후 기능 검사: FPGA 빌드의 `gate_sim/result.json`
- 기존 경로 단절 검사: FPGA 빌드의 `decode_pipeline_audit.txt`, `decode_pipeline_pc_paths.rpt`

아래 별도 면적 개선 절의 수치는 이 파이프라인을 넣기 **직전 버전**의 결과다.
[직전 버전 검증 기록](docs/validation/oryukdo_gen2_before_decode_pipeline.json)

### 직전 버전: 완료 테이블 면적 개선

면적 개선 후 RTL은 통합 8개 구성과 완료 FIFO/NEL 단위 검사 3개, 합계 **11개
테스트를 통과**했다. 동일한 32엔트리 설정에서 합성과 최적화를 완료했고,
**Vivado 2022.2 합성 netlist의 기능 시뮬레이션도 통과**했다. 배치·배선도 완료했다.

이번 개선 내용:

- 오륙도용 NEL을 `U_NEL`로 분리했다. 원본 을숙도의 `new_entry_logic`와
  IST/PRM/RS 코드는 변경하지 않았다. 기존 NEL 파이프라인을 그대로 복제한 것은
  아니며, 복구 가능한 매핑과 한 단계 IST 전달 버퍼를 오륙도용 NEL로 묶었다.
- IST가 막혀 있는 동안 발생한 WBC를 전달 버퍼에 반영하고, 전달 당일의 WBC도
  Ready 비트로 우회 전달한다.
- EX 5개와 메모리의 완료를 각 2칸 FIFO에 받은 뒤, 슬롯 짝수·홀수별 최대
  1개씩 처리한다. 최대 처리량은 2개/사이클이며 같은 뱅크 집중이나 FIFO head
  충돌 시 더 낮아질 수 있다. FIFO가 가득 차면 해당 생산자를 멈춘다.
- 뱅크 출력에 레지스터를 추가하여 FIFO 선택부터 IST Ready 갱신까지 이어지는
  경로를 분리했다. 출력이 막히면 해당 뱅크의 결과를 유지한다. 서로 다른 뱅크의
  완료 순서는 바뀔 수 있으며, 명령 확정 순서는 frontier가 계속 보장한다.
- 완료 테이블을 고정 명령 정보, 상태 플래그, 다음 PC/예외 정보로 분리했다.
  각 완료 뱅크는 자신의 슬롯들만 갱신한다. 예측 다음 PC를 실제 다음 PC로
  덮어써서 명령당 PC 필드 32비트를 줄였다. generation/epoch는 32비트를 유지했다.
- FIFO 접수와 완료 처리를 분리했고, 복구 시 FIFO도 비운다. 접수된 중복 결과는
  테이블에 기록되기 전에도 거부한다. 준비 완료 통지는 실제 처리와 맞춘다.

동일 조건의 `opt_design` 후 비교(배치·배선 전):

| 항목 | 개선 전 | 개선 후 |
| --- | ---: | ---: |
| 전체 LUT | 55,373 | 46,902 (15.3% 감소) |
| Frontier LUT | 21,795 | 11,350 (47.9% 감소) |
| 완료 FIFO와 뱅크 출력 LUT | 없음 | 3,604 |
| FF | 22,789 | 23,295 |
| BRAM36 | 42 | 42 |
| 70MHz setup slack | -6.638ns | -3.285ns |
| 최장 데이터 경로 | 20.791ns | 17.438ns |

엔트리 수, PHY/RS 크기, generation 폭을 줄이지 않은 비교다. 새 FIFO와 출력
레지스터 때문에 FF는 506개 증가했지만 LUT는 8,471개 줄었다. 개선 후 LUT는
Zynq-7020 용량의 88.16%다. 배치·배선 후에는 물리적 LUT 묶음 구성 때문에
47,656 LUT(89.58%)가 되었으며 FF와 BRAM은 그대로다.
이 단계의 최장 경로는 fetch PC에서 입력 허용·할당 제어를 거쳐 메모리 추적
엔트리의 generation으로 들어가는 경로다.

최종 배선의 70MHz setup slack은 -5.840ns, hold slack은 +0.057ns다.
최장 데이터 경로는 19.825ns / 32 logic levels이며, fetch PC에서 메모리 추적
generation으로 이어진다. 70MHz 목표는 충족하지 못했다.

배선 완료 후 동일한 배선을 고정하고 클럭 제약을 바꿔 전체 setup/hold/pulse-width
보고서를 다시 생성했다. 통과 경계는 **49.6MHz**이며, 여유를 둔 **45MHz**도 통과했다.

| 고정 배선 검사 클럭 | Setup slack | Hold slack | 전체 타이밍 |
| --- | ---: | ---: | --- |
| 45.0MHz | +2.096ns | +0.057ns | 통과 |
| 49.6MHz | +0.035ns | +0.057ns | 통과 |
| 49.7MHz | -0.005ns | +0.057ns | 실패 |
| 70MHz | -5.840ns | +0.057ns | 실패 |

이는 70MHz로 합성·배치·배선한 결과의 **고정 배선 STA**다. 45MHz 또는 49.6MHz로
처음부터 재합성·재배치한 결과나 보드 실측 클럭은 아니다. 두 통과 클럭의
checkpoint와 XDC는 빌드의 `sweep/`에 저장했다. 53,456개 routable net 전부
배선되었고 routing error는 0개다. 래치·블랙박스·조합 루프·클럭 없는 내부 경로는
0개이며, RAM 비동기 제어, routable load가 없는 출력 net, OOC에서 PS7 블록이
없는 것에 대한 DRC 경고는 남아 있다.

이 단계 보고서: [소스 해시·테스트 설정·자원·타이밍 기록](docs/validation/oryukdo_gen2_before_decode_pipeline.json).
원본 보고서와 checkpoint는 `gen2/build/oryukdo_area_pipelined32_70mhz`에 있다.
기능 검증은 `gen2/build/oryukdo_area_pipelined_regression` 및 해당 FPGA 빌드의
`gate_sim/result.json`에 기록했다. 기본 128엔트리 구성은 RTL 검증 범위이며,
위 FPGA 수치와 구분한다.

### 개선 전 비교 기준

개선 전 RTL은 통합 8개 구성의 회귀 검증을 통과했다. 별도로 기존 을숙도 경로의
7개 회귀 검사도 통과했다. CSR의 양방향 직렬화와 fetch epoch 갱신을 포함하는
개선 전 RTL의 **32엔트리 구성은 합성 후 기능 시뮬레이션도 통과**했다.
기본 128엔트리 구성은 RTL 회귀 검증까지 통과했으며, FPGA 자원이나
배치·배선 결과를 측정한 구성은 아니다.

32엔트리 비교 구성은 2 decode / 5 EX lanes, PHY=64, RS_DEPTH=128,
GEN_W=EPOCH_W=32, 70MHz 제약으로 Vivado 2022.2에서 실행했다.
아래 수치는 `opt_design` 후이며 **배치·배선 전**이다.

| 항목 | 결과 |
| --- | --- |
| LUT | 55,373 / 53,200 — PYNQ-Z2 용량 초과 |
| FF | 22,789 |
| BRAM36 | 42 |
| 래치 / 블랙박스 | 0 / 0 |
| 조합 루프 / 클럭 없는 내부 경로 | 0 / 0 |
| 70MHz setup slack | -6.638ns |
| 최장 데이터 경로 | 20.791ns, 36 logic levels |
| 배치·배선 / 실측 가능한 최종 클럭 | 미완료 / 미확정 |

자원 초과로 빌드가 `DEVICE_CAPACITY_EXCEEDED`에서 종료되었다. 기능 구현은
검증했지만 이 구성으로 PYNQ-Z2에 올릴 수 있다고 볼 수는 없다. 가장 큰 새 블록은
`U_FRONTIER`의 21,795 LUT이며, 최장 경로는 `U_MEMORY` generation 상태에서
입력 허용·할당 제어를 거쳐 다시 generation 상태로 돌아가는 경로다.
이번 개선은 이 완료 테이블의 다중 접근 회로와 완료 결과에서 입력 허용으로
이어지는 경로를 대상으로 했다. 개선 후에도 fetch PC 확인과 할당 제어 경로는 남아 있다.
기존 을숙도 타이밍 문서는 오륙도의 타이밍 결과가 아니다.

[개선 전 소스 해시·테스트 설정·자원·타이밍 기록](docs/validation/oryukdo_gen2_before_area.json)
원본 보고서와 checkpoint는 `gen2/build/oryukdo_serial32_70mhz`에 있다.

**검증 도구는 Vivado 2022.2다.** 2020.2는 개선 전의 동일한 8엔트리 RTL을
합성했을 때 `o_result_accept`, `o_agu_ready`, 메모리 주소/데이터 경로를 상수로
제거했다. 이전 128엔트리 2020.2 결과도 첫 발행부터 합성 후 기능 검사를
통과하지 못했다. 해당 빌드의 자원과 타이밍 수치는 유효한 오륙도 측정값이 아니다.
현재 빌드 스크립트는 주요 입출력 연결이 상수로 사라지면 실패 처리한다.
연결 검사는 기능 검증의 대체가 아니므로 별도 netlist 시뮬레이션도 제공한다.
개선 전 보고서에는 자원 초과 DRC가, 개선 후 보고서에는 남아 있는 RAM 비동기
제어 등의 경고가 기록되어 있다.

검증 명령(WSL/Linux, Verilator 필요):

```sh
python3 gen2/src/TB/run_oryukdo.py --jobs 2
python3 gen2/src/TB/run_lsq.py --jobs 2 --top tb_scheduler_flow
```

PYNQ-Z2 70MHz 비교 실행(Windows, Vivado 2022.2):

```powershell
python gen2/src/TB/run_oryukdo_fpga.py --entries 32 --output gen2/build/oryukdo_fpga_32 --mhz 70
python gen2/src/TB/run_oryukdo_netlist.py --build gen2/build/oryukdo_fpga_32
```

`--entries 32`로 추적 엔트리만 줄인 2d5i 구성을 비교할 수 있다. 기본값 128과
구분해서 결과를 기록한다. `--synth-only`는 배치/배선 없이 합성과 연결 검사,
기능 시뮬레이션용 netlist 생성까지만 실행한다.

합성용 복사본에만 기존 `$countones` 호환 변환을 적용하고 원본 및 합성 소스의
SHA-256을 기록한다. 스케줄러 내부 OOC 타이밍을 측정하며 보드 I/O 제약,
완성 CPU, bitstream 및 실제 보드 동작 검증을 포함하지 않는다.
