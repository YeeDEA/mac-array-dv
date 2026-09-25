# CMOS 로직 배경 — MAC PE는 결국 어떤 트랜지스터가 되는가

이 레포의 DUT(`rtl/mac_pe.sv`)는 `acc <= acc + a*b` 한 줄로 끝나지만, 합성하면 수천 개의 CMOS 게이트가 된다.
이 문서는 전자회로/디지털 설계 수업 내용을 정리하고, 그것이 이 프로젝트의 RTL과 어디서 만나는지 연결한다.

---

## 1. Complementary MOS: pull-up은 pMOS, pull-down은 nMOS

모든 정적(static) CMOS 게이트는 같은 구조를 가진다.

```
        VDD
         │
   ┌─────┴─────┐
   │  pull-up  │  ← pMOS 네트워크: 켜지면 Y를 1로 끌어올림
   │ (pMOS만)  │
   └─────┬─────┘
         ├──────── Y   (두 네트워크의 drain이 여기서 만남)
   ┌─────┴─────┐
   │ pull-down │  ← nMOS 네트워크: 켜지면 Y를 0으로 끌어내림
   │ (nMOS만)  │
   └─────┬─────┘
        GND
```

- 두 네트워크의 **drain을 출력 Y에 연결**한다. 어느 입력 조합에서든 **정확히 하나만** 도통해야 한다.
  - 둘 다 켜지면 → VDD–GND 단락 (정적 전류, 출력 전압 불확정)
  - 둘 다 꺼지면 → Y가 floating (high-Z) — 일반 게이트에선 버그, tristate에선 의도(§5)
- 그래서 pull-up 네트워크는 pull-down 네트워크의 **쌍대(dual)** 로 만든다: 직렬 ↔ 병렬을 바꾼다.

### 왜 역할이 이렇게 고정되나 (pMOS가 위, nMOS가 아래)

| | 잘 전달하는 값 | 약하게 전달하는 값 | 이유 |
|---|---|---|---|
| nMOS | **강한 0** | 약한 1 (VDD − V<sub>tn</sub>) | 소스가 올라가면 V<sub>GS</sub>가 줄어 V<sub>t</sub>에서 꺼짐 |
| pMOS | **강한 1** | 약한 0 (\|V<sub>tp</sub>\|) | 대칭적으로, 소스가 내려가면 꺼짐 |

nMOS로 1을 넘기려 하면 출력이 VDD − V<sub>t</sub>에서 멈춘다(degraded 1). 수업에서 본 **0.7 V 부근 값**은 이런 문턱/다이오드 전압 강하 계열의 숫자로,
"트랜지스터 하나를 지날 때마다 레벨이 깎인다"는 게 핵심이다. 그래서 nMOS는 GND 쪽(0 전달), pMOS는 VDD 쪽(1 전달)에만 둔다.
(Lecture 2의 전압 전달 특성 / noise margin 내용과 이어짐.)

부수 효과: pMOS는 홀 이동도가 낮아 같은 전류를 내려면 약 2배 폭이 필요하다 → NAND가 NOR보다 선호되는 이유(§3).

---

## 2. 직렬과 병렬 — 게이트가 "무엇을 계산하는가"

| 연결 | nMOS (pull-down) | pMOS (pull-up) |
|---|---|---|
| **직렬** | 입력이 **모두 1**일 때만 Y→0 (AND 조건) | 입력이 **모두 0**일 때만 Y→1 |
| **병렬** | **하나라도 1**이면 Y→0 (OR 조건) | **하나라도 0**이면 Y→1 |

> 필기 정리: "직렬이면 둘 다 같은 값일 때 동작" = 직렬 경로는 모든 트랜지스터가 켜져야 도통.
> "병렬이면 하나라도 0이면 Y가 1" = 병렬 pMOS 중 하나만 켜져도 VDD에 연결.

CMOS 게이트는 본질적으로 **반전(inverting)** 한다. pull-down이 f를 계산하면 출력은 ¬f.

---

## 3. 기본 게이트

### NAND2
- pull-down: nMOS A, B **직렬** → A·B=1일 때 Y=0
- pull-up: pMOS A, B **병렬** → 하나라도 0이면 Y=1
- Y = ¬(A·B), 트랜지스터 4개

### NOR2
- pull-down: nMOS **병렬**, pull-up: pMOS **직렬**
- Y = ¬(A+B), 트랜지스터 4개. 직렬 pMOS(느림)가 있어 NAND보다 불리.

### NAND3 — "3개가 동시에 1이면 0 출력?" → **맞다**
- nMOS 3개 직렬: A=B=C=1일 때만 GND까지 경로가 생겨 Y=0
- pMOS 3개 병렬: 그 외 7가지 경우엔 최소 하나가 켜져 Y=1
- 입력이 늘수록 직렬 스택이 길어져 저항·지연 증가 → 실무에선 fan-in 3~4 정도에서 끊고 트리로 나눈다.

### 복합 게이트 (AOI/OAI) — "다양한 논리회로를 pMOS/nMOS로"
임의의 반전 함수는 pull-down에 식을 그대로, pull-up에 쌍대를 넣어 한 단으로 만들 수 있다.

예) Y = ¬(A·B + C) (AOI21)
- pull-down: (A 직렬 B) ‖ C
- pull-up: (A ‖ B) 직렬 C
- 트랜지스터 6개 — AND + NOR로 따로 만들면 10개.

비반전 함수(AND, OR, XOR의 일부)는 뒤에 인버터가 한 단 더 붙는다.

---

## 4. 이 프로젝트와의 연결: `a*b` 와 `acc + prod`

| RTL | 합성 후 대략적인 게이트 구성 |
|---|---|
| `prod = a * b` (8b×8b signed) | 부분곱 64개 = **AND2** (NAND+INV) 64개, Baugh-Wooley 방식이면 부호 비트 쪽 일부는 NAND 그대로 사용 → Wallace/Dadda 트리의 **full adder** 들로 압축 |
| `acc + prod` (32b) | full adder 체인/캐리 룩어헤드. FA 1개 = 합(XOR3) + 캐리(majority, **AOI 형태의 복합 게이트**) — 미러 가산기 기준 28T |
| `if (clr) … else if (en) …` | 누산기 입력 앞의 **2:1 MUX** (§5) |
| `always_ff` | 전송 게이트 기반 master-slave D 플립플롭 |

그래서 README의 "PE 16개"는 대략 **곱셈기 16개 + 32b 가산기 16개 + 512개 FF** 다. 게이트 수 실측은 ROADMAP의 Yosys 합성 리포트 항목에서 다룬다.

주입 버그와의 연결도 있다:
- `BUG4` (b를 unsigned로 확장) — Baugh-Wooley에서 부호 비트 부분곱을 NAND 대신 AND로 넣는 실수와 같은 종류.
- `BUG1` (16비트에서 wrap) — 가산기 체인 캐리를 중간에서 끊은 것과 같다.

---

## 5. Tristate 버퍼와 MUX

### Tristate 버퍼
- 입력 A, enable EN, 출력 Y
- EN=1: Y = A, EN=0: **pull-up/pull-down 둘 다 꺼짐** → Y = Z (high-impedance)
- 구조: 인버터의 pMOS 위/nMOS 아래에 EN으로 제어되는 트랜지스터를 한 개씩 직렬로 추가(스택 4T) — §1에서 "둘 다 꺼짐 = 버그"였던 상태를 일부러 쓰는 것.

### Tristate 2개로 2:1 MUX
```
 D0 ──[TRI, EN = ¬S]──┐
                      ├── Y
 D1 ──[TRI, EN =  S]──┘
```
- S=0: 위 버퍼만 구동 → Y = D0 / S=1: Y = D1
- 두 enable이 **절대 동시에 1이 되면 안 된다** (bus contention = §1의 단락). 선택 신호 전환 순간의 겹침이 실제 설계 이슈.
- N:1로 확장하면 공유 버스가 된다 → 이 레포 상위 경험인 `digital-electronics-16bit-bus-report`(16비트 버스 설계)와 같은 원리.

### 칩 내부에선?
ASIC/FPGA 내부 로직에선 tristate 대신 **전송 게이트(transmission gate) MUX** 나 AND-OR MUX를 쓴다. FPGA 패브릭엔 내부 tristate가 없어서
Vivado는 내부 `'z` 버스를 MUX로 바꾼다. 이 레포의 RTL이 `'z`를 전혀 쓰지 않는 이유이기도 하다 — tristate는 I/O 패드에서만.

검증 관점에서 이 문제는 이미 레포에 들어가 있다: 스코어보드의 **X-check**(5b33a18)는 출력에 X/Z가 섞이면 실패시키는데,
실리콘이라면 floating 노드나 contention에 해당하는 상황을 시뮬레이션 단계에서 잡는 장치다.

---

## 6. 요약

1. pMOS는 1을, nMOS는 0을 강하게 전달한다 → pMOS는 pull-up, nMOS는 pull-down.
2. pull-down에 식(직렬=AND, 병렬=OR)을 넣고 pull-up엔 쌍대를 넣으면 반전 게이트가 된다.
3. NAND3 = nMOS 3개 직렬: 셋 다 1일 때만 0.
4. MAC PE = AND 부분곱 + full adder 트리 + MUX + FF. 곱셈기가 면적 대부분.
5. Tristate 2개 + 반대 enable = 2:1 MUX. 칩 내부에선 contention 위험 때문에 전송 게이트/논리 MUX로 대체.
