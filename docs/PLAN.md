# Project Plan — "설계 25 · 검증 60 · 포장 15"

기간: 2026.08.13 → 12.31 (약 20주 · 주 12~15h) · Vivado 2020.2 시뮬레이션 온리

**절대 규칙: DUT를 키우고 싶어질 때마다 이 줄을 읽는다 — 채용 요건은 검증이다. DUT는 소품이다.**

## Phase 0 — 부트스트랩 (8/13 ~ 8/31)
- W1: 레포 생성 · SV 리프레시(logic/interface/class) · verification_plan.md 뼈대 ★
- W2: `mac_pe.sv` (signed INT8, acc = 16+guard) · 방향성 셀프체킹 TB 1000회
- W3: 4×4 조립 + 로딩 FSM · Python 골든모델 대조 → **M0**
- 킬스위치: W3 말 M0 미달 → 2×2 축소

## Phase 1 — SVA (9/1 ~ 9/21)
- W4: valid/ready interface 정의
- W5: SVA 프로토콜 3~5 + 무결성 2~3
- W6: 버그 1개 주입 → SVA 위반 파형 캡처 → **M1**

## Phase 2 — UVM (9/22 ~ 10/31) ★ 본편
- W7: xsim UVM 플로우 (`-L uvm`, Hello UVM)
- W8: seq_item + sequencer + driver
- W9: monitor + analysis port + 골든모델 연결
- W10: scoreboard + 첫 constrained-random — 킬스위치: 미작동 시 컴포넌트 축소(agent 1, seq 1)
- W11: smoke / random / corner 테스트 3종
- W12: 버퍼 → **M2**: `make regress SEEDS=20` 무감독 통과

## Phase 3 — 커버리지 + 회귀 + 버그헌트 (11/1 ~ 11/30)
- W13: covergroup (값 빈, 시나리오, cross 1~2)
- W14: xsim 커버리지 한계 → 폴백 A: Python 자작 커버리지 / 폴백 B: Verilator+cocotb
- W15: 회귀 스크립트 완성 (시드 스윕 → 실패 재현 커맨드 → 병합 요약)
- W16: 버그 5개 주입 헌트 → bug_log.md → **M3**

## Phase 4 — 포장 (12/1 ~ 12/31)
- W17: README 영문 완성(다이어그램·결과표)
- W18: verification_plan 최종화
- W19: 레주메 숫자 채움 · LinkedIn · STAR 5개
- W20: (여유) cocotb 미니 포트 or FIFO IP 재사용 데모

## 위험 관리
| 위험 | 신호 | 대응 |
|---|---|---|
| xsim UVM 특이 동작 | W7 에러 지옥 | 한 주 통째로 환경에. 안 되면 Verilator+cocotb 전환 |
| DUT 확장 유혹 | INT4·8×8 욕심 | 금지. Phase 4 이후에만 |
| 3주 정체 | 같은 마일스톤 | 범위 축소(2×2/빈 절반). 완성 > 규모 |
| 학기 부하 | 주 8h 미만 2주 | Phase 2를 W14까지 연장, W14 폴백 주 삭제 |
