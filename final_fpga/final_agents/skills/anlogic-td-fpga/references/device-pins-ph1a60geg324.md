# Device pin reference - PH1A60GEG324 (family ph1, speed 3)

Auto-generated from TD 6.2.1 `query_current_package` output. Regenerate for any other device with:

```tcl
import_device ph1_60.db -package PH1A60GEG324 -speed 3
query_current_package -fio         ;# all fabric I/O
query_current_package -clock_io    ;# clock-capable pads (use these for clocks!)
query_current_package -lvds        ;# LVDS pairs
query_current_package -single_ended;# single-ended capable
```

The `pe` column is what TD accepts as a `LOCATION` in a `set_pin_assignment` statement (case-insensitive: `a10` and `A10` both work).

## Clock-capable pads (24 rows; blank Package pin = pad not bonded out)

| Sector | Grid loc | Package pin | PE name | Config | IntBank | ExtBank |
|---|---|---|---|---|---|---|
| 0 | x0y20z0 | B8 | b8 | gclkio2 | 11 | 11 |
| 0 | x0y20z2 | C9 | c9 | gclkio3 | 11 | 11 |
| 0 | x0y17z0 | A10 | a10 | gclkio0 | 11 | 11 |
| 0 | x0y17z2 | C11 | c11 | gclkio1 | 11 | 11 |
| 0 | x55y17z2 | - | - | gclkio1 | - | - |
| 0 | x55y17z0 | - | - | gclkio0 | - | - |
| 0 | x55y20z2 | - | - | gclkio3 | - | - |
| 0 | x55y20z0 | - | - | gclkio2 | - | - |
| 1 | x0y60z0 | P17 | p17 | gclkio2 | 12 | 12 |
| 1 | x0y60z2 | N15 | n15 | gclkio3 | 12 | 12 |
| 1 | x0y57z0 | T14 | t14 | gclkio0 | 12 | 12 |
| 1 | x0y57z2 | P15 | p15 | gclkio1 | 12 | 12 |
| 1 | x55y57z2 | N5 | n5 | gclkio1 | 32 | 32 |
| 1 | x55y57z0 | P4 | p4 | gclkio0 | 32 | 32 |
| 1 | x55y60z2 | R3 | r3 | gclkio3 | 32 | 32 |
| 1 | x55y60z0 | T5 | t5 | gclkio2 | 32 | 32 |
| 2 | x0y100z0 | D15 | d15 | gclkio2 | 13 | 13 |
| 2 | x0y100z2 | E15 | e15 | gclkio3 | 13 | 13 |
| 2 | x0y97z0 | F15 | f15 | gclkio0 | 13 | 13 |
| 2 | x0y97z2 | H16 | h16 | gclkio1 | 13 | 13 |
| 2 | x55y97z2 | F4 | f4 | gclkio1 | 33 | 33 |
| 2 | x55y97z0 | E2 | e2 | gclkio0 | 33 | 33 |
| 2 | x55y100z2 | D5 | d5 | gclkio3 | 33 | 33 |
| 2 | x55y100z0 | E3 | e3 | gclkio2 | 33 | 33 |

## All fabric I/O by bank (211 pads)

### Bank 0 (1 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 68 | `e9` | x5y71z0 | fio (hd) |

### Bank 11 (10 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 2 | `a10` | x0y17z0 | fio (hd) |
| 13 | `a8` | x0y20z1 | fio (hd) |
| 14 | `a9` | x0y17z1 | fio (hd) |
| 28 | `b8` | x0y20z0 | fio (hd) |
| 29 | `b9` | x0y20z3 | fio (hd) |
| 31 | `c10` | x0y17z3 | fio (hd) |
| 32 | `c11` | x0y17z2 | fio (hd) |
| 43 | `c9` | x0y20z2 | fio (hd) |
| 44 | `d10` | x0y7z3 | fio (hd) |
| 57 | `d9` | x0y30z1 | fio (hd) |

### Bank 12 (50 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 111 | `k17` | x0y76z2 | fio (hd) |
| 112 | `k18` | x0y76z3 | fio (hd) |
| 118 | `l13` | x0y70z0 | fio (hd) |
| 119 | `l14` | x0y76z0 | fio (hd) |
| 120 | `l15` | x0y73z2 | fio (hd) |
| 121 | `l16` | x0y73z3 | fio (hd) |
| 122 | `l18` | x0y73z0 | fio (hd) |
| 128 | `m13` | x0y70z1 | fio (hd) |
| 129 | `m14` | x0y76z1 | fio (hd) |
| 130 | `m16` | x0y63z0 | fio (hd) |
| 131 | `m17` | x0y63z1 | fio (hd) |
| 132 | `m18` | x0y73z1 | fio (hd) |
| 138 | `n14` | x0y67z0 | fio (hd) |
| 139 | `n15` | x0y60z2 | fio (hd) |
| 140 | `n16` | x0y60z3 | fio (hd) |
| 141 | `n17` | x0y63z2 | fio (hd) |
| 146 | `p14` | x0y67z1 | fio (hd) |
| 147 | `p15` | x0y57z2 | fio (hd) |
| 148 | `p17` | x0y60z0 | fio (hd) |
| 149 | `p18` | x0y63z3 | fio (hd) |
| 155 | `r10` | x0y40z0 | fio (hd) |
| 156 | `r11` | x0y79z3 | fio (hd) |
| 157 | `r12` | x0y70z2 | fio (hd) |
| 158 | `r13` | x0y70z3 | fio (hd) |
| 159 | `r15` | x0y57z3 | fio (hd) |
| 160 | `r16` | x0y54z2 | fio (hd) |
| 161 | `r17` | x0y60z1 | fio (hd) |
| 162 | `r18` | x0y67z2 | fio (hd) |
| 170 | `t10` | x0y41z1 | fio (hd) |
| 171 | `t11` | x0y47z2 | fio (hd) |
| 172 | `t13` | x0y41z2 | fio (hd) |
| 173 | `t14` | x0y57z0 | fio (hd) |
| 174 | `t15` | x0y57z1 | fio (hd) |
| 175 | `t16` | x0y54z3 | fio (hd) |
| 176 | `t18` | x0y67z3 | fio (hd) |
| 182 | `t9` | x0y41z0 | fio (hd) |
| 184 | `u11` | x0y47z3 | fio (hd) |
| 185 | `u12` | x0y47z0 | fio (hd) |
| 186 | `u13` | x0y41z3 | fio (hd) |
| 187 | `u14` | x0y44z0 | fio (hd) |
| 188 | `u16` | x0y50z0 | fio (hd) |
| 189 | `u17` | x0y50z2 | fio (hd) |
| 190 | `u18` | x0y50z3 | fio (hd) |
| 199 | `v10` | x0y44z2 | fio (hd) |
| 200 | `v11` | x0y44z3 | fio (hd) |
| 201 | `v12` | x0y47z1 | fio (hd) |
| 202 | `v14` | x0y44z1 | fio (hd) |
| 203 | `v15` | x0y54z0 | fio (hd) |
| 204 | `v16` | x0y54z1 | fio (hd) |
| 205 | `v17` | x0y50z1 | fio (hd) |

### Bank 13 (50 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 3 | `a11` | x0y113z1 | fio (hd) |
| 4 | `a13` | x0y103z2 | fio (hd) |
| 5 | `a14` | x0y103z3 | fio (hd) |
| 6 | `a15` | x0y107z0 | fio (hd) |
| 7 | `a16` | x0y107z1 | fio (hd) |
| 8 | `a18` | x0y103z1 | fio (hd) |
| 16 | `b11` | x0y113z0 | fio (hd) |
| 17 | `b12` | x0y113z3 | fio (hd) |
| 18 | `b13` | x0y116z0 | fio (hd) |
| 19 | `b14` | x0y116z1 | fio (hd) |
| 20 | `b16` | x0y107z2 | fio (hd) |
| 21 | `b17` | x0y107z3 | fio (hd) |
| 22 | `b18` | x0y103z0 | fio (hd) |
| 33 | `c12` | x0y113z2 | fio (hd) |
| 34 | `c14` | x0y116z3 | fio (hd) |
| 35 | `c15` | x0y100z1 | fio (hd) |
| 36 | `c16` | x0y87z0 | fio (hd) |
| 37 | `c17` | x0y87z1 | fio (hd) |
| 45 | `d12` | x0y110z0 | fio (hd) |
| 46 | `d13` | x0y110z1 | fio (hd) |
| 47 | `d14` | x0y116z2 | fio (hd) |
| 48 | `d15` | x0y100z0 | fio (hd) |
| 49 | `d17` | x0y94z1 | fio (hd) |
| 50 | `d18` | x0y84z3 | fio (hd) |
| 59 | `e15` | x0y100z2 | fio (hd) |
| 60 | `e16` | x0y100z3 | fio (hd) |
| 61 | `e17` | x0y94z0 | fio (hd) |
| 62 | `e18` | x0y84z2 | fio (hd) |
| 70 | `f13` | x0y110z2 | fio (hd) |
| 71 | `f14` | x0y110z3 | fio (hd) |
| 72 | `f15` | x0y97z0 | fio (hd) |
| 73 | `f16` | x0y97z1 | fio (hd) |
| 74 | `f18` | x0y84z1 | fio (hd) |
| 80 | `g13` | x0y119z3 | fio (hd) |
| 81 | `g14` | x0y94z3 | fio (hd) |
| 82 | `g16` | x0y97z3 | fio (hd) |
| 83 | `g17` | x0y90z1 | fio (hd) |
| 84 | `g18` | x0y84z0 | fio (hd) |
| 90 | `h14` | x0y94z2 | fio (hd) |
| 91 | `h15` | x0y87z3 | fio (hd) |
| 92 | `h16` | x0y97z2 | fio (hd) |
| 93 | `h17` | x0y90z0 | fio (hd) |
| 98 | `j13` | x0y90z3 | fio (hd) |
| 99 | `j14` | x0y87z2 | fio (hd) |
| 100 | `j15` | x0y81z1 | fio (hd) |
| 101 | `j17` | x0y81z2 | fio (hd) |
| 102 | `j18` | x0y81z3 | fio (hd) |
| 108 | `k13` | x0y90z2 | fio (hd) |
| 109 | `k15` | x0y81z0 | fio (hd) |
| 110 | `k16` | x0y80z0 | fio (hd) |

### Bank 32 (50 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 114 | `k3` | x55y76z0 | fio (hd) |
| 115 | `k5` | x55y70z2 | fio (hd) |
| 116 | `k6` | x55y79z3 | fio (hd) |
| 117 | `l1` | x55y76z2 | fio (hd) |
| 123 | `l3` | x55y76z1 | fio (hd) |
| 124 | `l4` | x55y70z3 | fio (hd) |
| 125 | `l5` | x55y70z1 | fio (hd) |
| 126 | `l6` | x55y70z0 | fio (hd) |
| 127 | `m1` | x55y76z3 | fio (hd) |
| 133 | `m2` | x55y73z1 | fio (hd) |
| 134 | `m3` | x55y73z0 | fio (hd) |
| 135 | `m4` | x55y54z0 | fio (hd) |
| 136 | `m6` | x55y50z0 | fio (hd) |
| 137 | `n1` | x55y73z3 | fio (hd) |
| 142 | `n2` | x55y73z2 | fio (hd) |
| 143 | `n4` | x55y54z1 | fio (hd) |
| 144 | `n5` | x55y57z2 | fio (hd) |
| 145 | `n6` | x55y50z1 | fio (hd) |
| 150 | `p2` | x55y54z2 | fio (hd) |
| 151 | `p3` | x55y57z1 | fio (hd) |
| 152 | `p4` | x55y57z0 | fio (hd) |
| 153 | `p5` | x55y57z3 | fio (hd) |
| 154 | `r1` | x55y50z2 | fio (hd) |
| 163 | `r2` | x55y54z3 | fio (hd) |
| 164 | `r3` | x55y60z2 | fio (hd) |
| 165 | `r5` | x55y47z3 | fio (hd) |
| 166 | `r6` | x55y47z2 | fio (hd) |
| 167 | `r7` | x55y41z2 | fio (hd) |
| 168 | `r8` | x55y41z0 | fio (hd) |
| 169 | `t1` | x55y50z3 | fio (hd) |
| 177 | `t3` | x55y60z3 | fio (hd) |
| 178 | `t4` | x55y60z1 | fio (hd) |
| 179 | `t5` | x55y60z0 | fio (hd) |
| 180 | `t6` | x55y41z3 | fio (hd) |
| 181 | `t8` | x55y41z1 | fio (hd) |
| 183 | `u1` | x55y67z2 | fio (hd) |
| 191 | `u2` | x55y63z2 | fio (hd) |
| 192 | `u3` | x55y67z1 | fio (hd) |
| 193 | `u4` | x55y67z0 | fio (hd) |
| 194 | `u6` | x55y44z1 | fio (hd) |
| 195 | `u7` | x55y44z0 | fio (hd) |
| 196 | `u8` | x55y40z0 | fio (hd) |
| 197 | `u9` | x55y44z2 | fio (hd) |
| 198 | `v1` | x55y67z3 | fio (hd) |
| 206 | `v2` | x55y63z3 | fio (hd) |
| 207 | `v4` | x55y63z1 | fio (hd) |
| 208 | `v5` | x55y63z0 | fio (hd) |
| 209 | `v6` | x55y47z1 | fio (hd) |
| 210 | `v7` | x55y47z0 | fio (hd) |
| 211 | `v9` | x55y44z3 | fio (hd) |

### Bank 33 (50 pads)

| Idx | PE (use as LOCATION) | Grid loc | Type |
|---|---|---|---|
| 1 | `a1` | x55y103z3 | fio (hd) |
| 9 | `a3` | x55y107z1 | fio (hd) |
| 10 | `a4` | x55y107z0 | fio (hd) |
| 11 | `a5` | x55y113z3 | fio (hd) |
| 12 | `a6` | x55y113z2 | fio (hd) |
| 15 | `b1` | x55y103z2 | fio (hd) |
| 23 | `b2` | x55y103z1 | fio (hd) |
| 24 | `b3` | x55y103z0 | fio (hd) |
| 25 | `b4` | x55y107z3 | fio (hd) |
| 26 | `b6` | x55y116z1 | fio (hd) |
| 27 | `b7` | x55y116z0 | fio (hd) |
| 30 | `c1` | x55y94z1 | fio (hd) |
| 38 | `c2` | x55y94z0 | fio (hd) |
| 39 | `c4` | x55y107z2 | fio (hd) |
| 40 | `c5` | x55y116z3 | fio (hd) |
| 41 | `c6` | x55y116z2 | fio (hd) |
| 42 | `c7` | x55y113z1 | fio (hd) |
| 51 | `d2` | x55y97z1 | fio (hd) |
| 52 | `d3` | x55y100z1 | fio (hd) |
| 53 | `d4` | x55y100z3 | fio (hd) |
| 54 | `d5` | x55y100z2 | fio (hd) |
| 55 | `d7` | x55y110z1 | fio (hd) |
| 56 | `d8` | x55y113z0 | fio (hd) |
| 58 | `e1` | x55y90z1 | fio (hd) |
| 63 | `e2` | x55y97z0 | fio (hd) |
| 64 | `e3` | x55y100z0 | fio (hd) |
| 65 | `e5` | x55y110z3 | fio (hd) |
| 66 | `e6` | x55y110z2 | fio (hd) |
| 67 | `e7` | x55y110z0 | fio (hd) |
| 69 | `f1` | x55y90z0 | fio (hd) |
| 75 | `f3` | x55y97z3 | fio (hd) |
| 76 | `f4` | x55y97z2 | fio (hd) |
| 77 | `f5` | x55y119z3 | fio (hd) |
| 78 | `f6` | x55y87z3 | fio (hd) |
| 79 | `g1` | x55y90z3 | fio (hd) |
| 85 | `g2` | x55y94z3 | fio (hd) |
| 86 | `g3` | x55y87z1 | fio (hd) |
| 87 | `g4` | x55y87z0 | fio (hd) |
| 88 | `g6` | x55y87z2 | fio (hd) |
| 89 | `h1` | x55y90z2 | fio (hd) |
| 94 | `h2` | x55y94z2 | fio (hd) |
| 95 | `h4` | x55y84z3 | fio (hd) |
| 96 | `h5` | x55y81z1 | fio (hd) |
| 97 | `h6` | x55y81z0 | fio (hd) |
| 103 | `j2` | x55y84z1 | fio (hd) |
| 104 | `j3` | x55y84z0 | fio (hd) |
| 105 | `j4` | x55y84z2 | fio (hd) |
| 106 | `j5` | x55y80z0 | fio (hd) |
| 107 | `k1` | x55y81z3 | fio (hd) |
| 113 | `k2` | x55y81z2 | fio (hd) |

## LVDS pairs

```
@@@LVDS_START
RUN-1002 : start command "query_current_package -lvds"
RUN-1001 : Input LVDS pairs in package PH1A60GEG324 : 
RUN-1001 : ---------------------------------------------------------------------------------------
RUN-1001 :    #   |  Type  |  IntBank  |  ExtBank  |  Name <[P],[N]>  |    Location <[P],[N]>     
RUN-1001 : ---------------------------------------------------------------------------------------
RUN-1001 :    1   |  LVDS  |    11     |    11     |    <A10 , A9>    |    <X0Y17Z0 , X0Y17Z1>    
RUN-1001 :    2   |  LVDS  |    13     |    13     |   <A13 , A14>    |   <X0Y103Z2 , X0Y103Z3>   
RUN-1001 :    3   |  LVDS  |    13     |    13     |   <A15 , A16>    |   <X0Y107Z0 , X0Y107Z1>   
RUN-1001 :    4   |  LVDS  |    33     |    33     |    <A4 , A3>     |  <X55Y107Z0 , X55Y107Z1>  
RUN-1001 :    5   |  LVDS  |    33     |    33     |    <A6 , A5>     |  <X55Y113Z2 , X55Y113Z3>  
RUN-1001 :    6   |  LVDS  |    33     |    33     |    <B1 , A1>     |  <X55Y103Z2 , X55Y103Z3>  
RUN-1001 :    7   |  LVDS  |    13     |    13     |   <B11 , A11>    |   <X0Y113Z0 , X0Y113Z1>   
RUN-1001 :    8   |  LVDS  |    13     |    13     |   <B13 , B14>    |   <X0Y116Z0 , X0Y116Z1>   
RUN-1001 :    9   |  LVDS  |    13     |    13     |   <B16 , B17>    |   <X0Y107Z2 , X0Y107Z3>   
RUN-1001 :   10   |  LVDS  |    13     |    13     |   <B18 , A18>    |   <X0Y103Z0 , X0Y103Z1>   
RUN-1001 :   11   |  LVDS  |    33     |    33     |    <B3 , B2>     |  <X55Y103Z0 , X55Y103Z1>  
RUN-1001 :   12   |  LVDS  |    33     |    33     |    <B7 , B6>     |  <X55Y116Z0 , X55Y116Z1>  
RUN-1001 :   13   |  LVDS  |    11     |    11     |    <B8 , A8>     |    <X0Y20Z0 , X0Y20Z1>    
RUN-1001 :   14   |  LVDS  |    11     |    11     |   <C11 , C10>    |    <X0Y17Z2 , X0Y17Z3>    
RUN-1001 :   15   |  LVDS  |    13     |    13     |   <C12 , B12>    |   <X0Y113Z2 , X0Y113Z3>   
RUN-1001 :   16   |  LVDS  |    13     |    13     |   <C16 , C17>    |    <X0Y87Z0 , X0Y87Z1>    
RUN-1001 :   17   |  LVDS  |    33     |    33     |    <C2 , C1>     |   <X55Y94Z0 , X55Y94Z1>   
RUN-1001 :   18   |  LVDS  |    33     |    33     |    <C4 , B4>     |  <X55Y107Z2 , X55Y107Z3>  
RUN-1001 :   19   |  LVDS  |    33     |    33     |    <C6 , C5>     |  <X55Y116Z2 , X55Y116Z3>  
RUN-1001 :   20   |  LVDS  |    11     |    11     |    <C9 , B9>     |    <X0Y20Z2 , X0Y20Z3>    
RUN-1001 :   21   |  LVDS  |    13     |    13     |   <D12 , D13>    |   <X0Y110Z0 , X0Y110Z1>   
RUN-1001 :   22   |  LVDS  |    13     |    13     |   <D14 , C14>    |   <X0Y116Z2 , X0Y116Z3>   
RUN-1001 :   23   |  LVDS  |    13     |    13     |   <D15 , C15>    |   <X0Y100Z0 , X0Y100Z1>   
RUN-1001 :   24   |  LVDS  |    33     |    33     |    <D5 , D4>     |  <X55Y100Z2 , X55Y100Z3>  
RUN-1001 :   25   |  LVDS  |    33     |    33     |    <D8 , C7>     |  <X55Y113Z0 , X55Y113Z1>  
RUN-1001 :   26   |  LVDS  |    13     |    13     |   <E15 , E16>    |   <X0Y100Z2 , X0Y100Z3>   
RUN-1001 :   27   |  LVDS  |    13     |    13     |   <E17 , D17>    |    <X0Y94Z0 , X0Y94Z1>    
RUN-1001 :   28   |  LVDS  |    13     |    13     |   <E18 , D18>    |    <X0Y84Z2 , X0Y84Z3>    
RUN-1001 :   29   |  LVDS  |    33     |    33     |    <E2 , D2>     |   <X55Y97Z0 , X55Y97Z1>   
RUN-1001 :   30   |  LVDS  |    33     |    33     |    <E3 , D3>     |  <X55Y100Z0 , X55Y100Z1>  
RUN-1001 :   31   |  LVDS  |    33     |    33     |    <E6 , E5>     |  <X55Y110Z2 , X55Y110Z3>  
RUN-1001 :   32   |  LVDS  |    33     |    33     |    <E7 , D7>     |  <X55Y110Z0 , X55Y110Z1>  
RUN-1001 :   33   |  LVDS  |    33     |    33     |    <F1 , E1>     |   <X55Y90Z0 , X55Y90Z1>   
RUN-1001 :   34   |  LVDS  |    13     |    13     |   <F13 , F14>    |   <X0Y110Z2 , X0Y110Z3>   
RUN-1001 :   35   |  LVDS  |    13     |    13     |   <F15 , F16>    |    <X0Y97Z0 , X0Y97Z1>    
RUN-1001 :   36   |  LVDS  |    33     |    33     |    <F4 , F3>     |   <X55Y97Z2 , X55Y97Z3>   
RUN-1001 :   37
```