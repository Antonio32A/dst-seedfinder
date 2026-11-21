# Tasks megagraph

This data was computed by generating 1 million forest and 1 million cave worlds on version 762172 on Windows. Some seeds
are not possible (usually the worldgen algorithm gives up), so in this case 7,469 forest and 23,845 cave seeds failed to
generate.

## Forest

25 tasks and 175 different connections between them, from 992,531 worlds.

```mermaid
---
title: How the forest tasks connect
---
flowchart LR
    classDef optional stroke-dasharray: 5 5
    spawn(["Florid Postern"])
    t0["Make a pick (Spawn)"]
    t1["Dig that rock (Mosaic)"]
    t2["Great Plains (Savanna)"]
    t3["Squeltch (Marsh)"]
    t4["Beeeees! (Bee Queen)"]
    t5["Speak to the king (Pig King)"]
    t6["Forest hunters (Moonstone Forest)"]
    t7["For a nice walk (Mandrake Forest)"]
    t8["Badlands (Dragonfly Desert)"]
    t9["Lightning Bluff (Oasis Desert)"]
    t10["Befriend the pigs (Pig Forest)<br/>in 49.9% of worlds"]:::optional
    t11["Kill the spiders (Spider Quarry)<br/>in 50.0% of worlds"]:::optional
    t12["Killer bees! (Killer Bee Field)<br/>in 49.9% of worlds"]:::optional
    t13["Make a Beehat (Bee Meteor Biome)<br/>in 50.0% of worlds"]:::optional
    t14["The hunters (Triple MacTusk)<br/>in 50.0% of worlds"]:::optional
    t15["Magic meadow (Frog Ponds)<br/>in 50.1% of worlds"]:::optional
    t16["Frogs and bugs (Frog Ponds and Beehives)<br/>in 50.0% of worlds"]:::optional
    t17["Mole Colony Deciduous (Second Deciduous)<br/>in 49.9% of worlds"]:::optional
    t18["Mole Colony Rocks (Rocky Biome)<br/>in 50.0% of worlds"]:::optional
    t19["MooseBreedingTask (Quad Moose)<br/>in 50.1% of worlds"]:::optional
    t20["MoonIsland_Beach"]
    t21["MoonIsland_Baths"]
    t22["MoonIsland_Forest"]
    t23["MoonIsland_Mine"]
    t24["MoonIsland_IslandShards"]
    spawn ==>|"100%"| t0
    t0 ==>|"100%"| t1
    t0 ==>|"50.0%"| t16
    t0 ==>|"33.4%"| t2
    t0 ==>|"32.5%"| t15
    t0 ==>|"31.9%"| t10
    t0 ==>|"30.3%"| t4
    t0 -->|"22.6%"| t7
    t0 -->|"15.4%"| t3
    t0 -->|"14.7%"| t19
    t0 -->|"11.8%"| t17
    t0 -->|"11.6%"| t18
    t0 -->|"5.2%"| t11
    t0 -.->|"2.1%"| t13
    t1 -->|"18.5%"| t5
    t1 -->|"10.4%"| t2
    t1 -->|"9.4%"| t4
    t1 -->|"6.2%"| t18
    t1 -.->|"3.8%"| t17
    t1 -.->|"2.2%"| t13
    t1 -.->|"1.5%"| t15
    t1 -.->|"1.5%"| t10
    t2 -->|"20.9%"| t7
    t2 -->|"18.4%"| t5
    t2 -->|"16.4%"| t4
    t2 -->|"15.2%"| t3
    t2 -->|"9.2%"| t17
    t2 -->|"7.2%"| t19
    t2 -->|"6.3%"| t18
    t2 -.->|"2.2%"| t13
    t2 -.->|"0.82%"| t15
    t3 -->|"15.2%"| t6
    t3 -->|"15.2%"| t8
    t3 -->|"15.0%"| t9
    t3 -->|"8.8%"| t13
    t3 -->|"6.7%"| t11
    t3 -->|"6.5%"| t14
    t3 -->|"6.5%"| t12
    t4 -->|"19.7%"| t7
    t4 -->|"17.6%"| t5
    t4 -->|"17.3%"| t8
    t4 -->|"15.3%"| t6
    t4 -->|"14.7%"| t3
    t4 -->|"10.1%"| t14
    t4 -->|"8.3%"| t2
    t4 -->|"8.0%"| t17
    t4 -->|"6.3%"| t19
    t4 -->|"5.9%"| t18
    t4 -->|"5.5%"| t11
    t4 -.->|"2.2%"| t13
    t4 -.->|"0.65%"| t10
    t4 -.->|"0.65%"| t15
    t4 -.->|"0.5%"| t9
    t4 -.->|"0.32%"| t12
    t5 -->|"17.0%"| t8
    t5 -->|"15.1%"| t3
    t5 -->|"14.9%"| t6
    t5 -->|"10.1%"| t14
    t5 -->|"5.2%"| t11
    t5 -->|"5.1%"| t12
    t5 -.->|"3.8%"| t19
    t5 -.->|"0.97%"| t7
    t5 -.->|"0.073%"| t9
    t6 -->|"13.9%"| t9
    t6 -->|"8.8%"| t8
    t6 -->|"8.4%"| t12
    t6 -->|"6.0%"| t13
    t6 -.->|"4.5%"| t11
    t6 -.->|"4.2%"| t14
    t7 -->|"16.7%"| t5
    t7 -->|"14.9%"| t3
    t7 -->|"5.6%"| t18
    t7 -.->|"3.8%"| t19
    t7 -.->|"2.1%"| t13
    t7 -.->|"1.8%"| t4
    t7 -.->|"1.7%"| t2
    t7 -.->|"0.85%"| t17
    t8 -->|"15.0%"| t6
    t8 -->|"9.0%"| t9
    t8 -.->|"4.8%"| t14
    t8 -.->|"4.7%"| t11
    t8 -.->|"4.2%"| t13
    t8 -.->|"3.6%"| t12
    t9 -->|"16.0%"| t12
    t9 -->|"9.6%"| t13
    t9 -->|"7.5%"| t6
    t9 -->|"7.5%"| t8
    t9 -.->|"3.9%"| t11
    t9 -.->|"2.9%"| t14
    t10 -->|"13.5%"| t2
    t10 -->|"11.7%"| t4
    t10 -->|"10.3%"| t7
    t10 -->|"8.3%"| t5
    t10 -->|"6.9%"| t3
    t10 -->|"5.7%"| t19
    t10 -.->|"4.7%"| t17
    t10 -.->|"3.6%"| t15
    t10 -.->|"3.4%"| t18
    t10 -.->|"2.1%"| t11
    t10 -.->|"0.75%"| t13
    t11 ==>|"38.7%"| t9
    t11 -.->|"4.8%"| t8
    t11 -.->|"4.0%"| t6
    t11 -.->|"2.4%"| t12
    t11 -.->|"2.2%"| t13
    t11 -.->|"1.7%"| t14
    t12 -->|"10.3%"| t9
    t12 -->|"6.8%"| t8
    t12 -->|"6.8%"| t6
    t12 -.->|"3.8%"| t13
    t12 -.->|"2.5%"| t14
    t12 -.->|"2.1%"| t11
    t13 -->|"7.3%"| t9
    t13 -.->|"5.0%"| t12
    t13 -.->|"2.5%"| t6
    t13 -.->|"2.5%"| t8
    t13 -.->|"0.88%"| t14
    t13 -.->|"0.88%"| t11
    t14 -->|"8.2%"| t8
    t14 -->|"7.5%"| t6
    t14 -.->|"2.3%"| t11
    t14 -.->|"0.25%"| t9
    t14 -.->|"0.12%"| t12
    t14 -.->|"0.066%"| t13
    t15 -->|"13.7%"| t2
    t15 -->|"11.9%"| t4
    t15 -->|"6.2%"| t10
    t15 -.->|"4.9%"| t17
    t15 -.->|"3.6%"| t18
    t15 -.->|"0.78%"| t13
    t16 -->|"12.9%"| t2
    t16 -->|"12.4%"| t4
    t16 -->|"11.0%"| t15
    t16 -->|"10.6%"| t7
    t16 -->|"9.7%"| t10
    t16 -->|"8.2%"| t5
    t16 -->|"7.1%"| t8
    t16 -->|"6.9%"| t3
    t16 -->|"6.7%"| t19
    t16 -->|"6.4%"| t6
    t16 -.->|"4.9%"| t17
    t16 -.->|"3.9%"| t18
    t16 -.->|"3.7%"| t14
    t16 -.->|"2.1%"| t11
    t16 -.->|"0.76%"| t13
    t17 -->|"9.5%"| t7
    t17 -->|"7.9%"| t5
    t17 -->|"6.7%"| t3
    t17 -.->|"2.3%"| t18
    t17 -.->|"2.2%"| t4
    t17 -.->|"2.0%"| t19
    t17 -.->|"1.8%"| t2
    t17 -.->|"0.82%"| t13
    t17 -.->|"0.65%"| t9
    t17 -.->|"0.64%"| t8
    t17 -.->|"0.64%"| t6
    t17 -.->|"0.51%"| t14
    t17 -.->|"0.48%"| t12
    t17 -.->|"0.41%"| t11
    t19 -->|"5.3%"| t7
    t19 -.->|"4.4%"| t11
    t19 -.->|"4.4%"| t5
    t19 -.->|"4.3%"| t2
    t19 -.->|"4.2%"| t6
    t19 -.->|"4.2%"| t8
    t19 -.->|"4.2%"| t9
    t19 -.->|"4.1%"| t3
    t19 -.->|"3.8%"| t4
    t19 -.->|"2.2%"| t14
    t19 -.->|"2.2%"| t12
    t19 -.->|"1.7%"| t17
    t19 -.->|"1.5%"| t13
    t19 -.->|"1.3%"| t18
    t20 ==>|"100%"| t21
    t21 ==>|"100%"| t22
    t21 ==>|"100%"| t23
```

## Caves

51 tasks and 223 different connections between them, from 976,155 worlds.

```mermaid
---
title: How the caves tasks connect
---
flowchart LR
    classDef optional stroke-dasharray: 5 5
    spawn(["Florid Postern"])
    t0["ArchiveMaze"]
    t1["AtriumMaze"]
    t2["BigBatCave"]
    t3["BlueForest"]
    t4["CaveExitTask1"]
    t5["CaveExitTask2"]
    t6["CaveExitTask3"]
    t7["CaveExitTask4"]
    t8["CaveExitTask5"]
    t9["CaveExitTask6"]
    t10["CaveExitTask7"]
    t11["CaveExitTask8"]
    t12["CaveExitTask9"]
    t13["CaveExitTask10"]
    t14["CentipedeCaveTask"]
    t15["GreenForest"]
    t16["LichenLand"]
    t17["Military"]
    t18["MoonCaveForest"]
    t19["MudCave"]
    t20["MudLights"]
    t21["MudPit"]
    t22["MudWorld"]
    t23["RedForest"]
    t24["Residential"]
    t25["RockyLand"]
    t26["Sacred"]
    t27["SacredAltar"]
    t28["SpillagmiteCaverns"]
    t29["TheLabyrinth"]
    t30["ToadStoolTask1"]
    t31["ToadStoolTask2"]
    t32["ToadStoolTask3"]
    t33["BatCloister<br/>in 44.5% of worlds"]:::optional
    t34["CaveJungle<br/>in 44.3% of worlds"]:::optional
    t35["CaveSwamp<br/>in 44.5% of worlds"]:::optional
    t36["FungalNoiseForest<br/>in 44.6% of worlds"]:::optional
    t37["FungalNoiseMeadow<br/>in 44.3% of worlds"]:::optional
    t38["MilitaryPits<br/>in 43.3% of worlds"]:::optional
    t39["MoreAltars<br/>in 44.7% of worlds"]:::optional
    t40["MuddySacred<br/>in 44.5% of worlds"]:::optional
    t41["PleasantSinkhole<br/>in 44.6% of worlds"]:::optional
    t42["RabbitCity<br/>in 44.6% of worlds"]:::optional
    t43["RabbitSpiderWar<br/>in 44.6% of worlds"]:::optional
    t44["RabbitTown<br/>in 44.6% of worlds"]:::optional
    t45["Residential2<br/>in 44.4% of worlds"]:::optional
    t46["Residential3<br/>in 44.4% of worlds"]:::optional
    t47["SacredDanger<br/>in 44.5% of worlds"]:::optional
    t48["SpiderLand<br/>in 44.4% of worlds"]:::optional
    t49["SwampySinkhole<br/>in 44.6% of worlds"]:::optional
    t50["UndergroundForest<br/>in 44.6% of worlds"]:::optional
    spawn -->|"10.0%"| t7
    spawn -->|"10.0%"| t9
    spawn -->|"10.0%"| t13
    spawn -->|"10.0%"| t8
    spawn -->|"10.0%"| t4
    spawn -->|"10.0%"| t6
    spawn -->|"10.0%"| t10
    spawn -->|"10.0%"| t11
    spawn -->|"10.0%"| t5
    spawn -->|"9.9%"| t12
    t2 ==>|"44.3%"| t37
    t2 -->|"8.5%"| t33
    t2 -->|"5.4%"| t42
    t2 -->|"5.4%"| t35
    t2 -.->|"4.6%"| t31
    t2 -.->|"2.5%"| t44
    t2 -.->|"1.6%"| t48
    t2 -.->|"0.76%"| t43
    t2 -.->|"0.64%"| t41
    t2 -.->|"0.59%"| t36
    t2 -.->|"0.31%"| t49
    t2 -.->|"0.1%"| t32
    t2 -.->|"0.032%"| t50
    t3 ==>|"100%"| t18
    t3 ==>|"45.6%"| t4
    t3 ==>|"39.0%"| t5
    t3 ==>|"38.7%"| t6
    t3 ==>|"29.5%"| t7
    t9 -.->|"0.015%"| t13
    t9 -.->|"0.015%"| t8
    t9 -.->|"0.013%"| t10
    t9 -.->|"0.013%"| t11
    t9 -.->|"0.012%"| t12
    t9 -.->|"0.0002%"| t14
    t13 -.->|"0.17%"| t8
    t13 -.->|"0.17%"| t11
    t13 -.->|"0.17%"| t12
    t13 -.->|"0.16%"| t10
    t13 -.->|"0.11%"| t9
    t13 -.->|"0.0017%"| t14
    t15 ==>|"49.7%"| t31
    t15 ==>|"46.9%"| t5
    t15 ==>|"38.2%"| t6
    t15 ==>|"37.4%"| t4
    t15 ==>|"37.0%"| t7
    t15 -->|"16.4%"| t33
    t15 -->|"16.0%"| t43
    t15 -->|"15.2%"| t48
    t15 -->|"14.9%"| t35
    t15 -->|"11.4%"| t42
    t15 -->|"10.8%"| t36
    t15 -->|"10.4%"| t32
    t15 -->|"10.1%"| t49
    t15 -->|"8.7%"| t41
    t15 -->|"7.5%"| t44
    t15 -.->|"2.9%"| t50
    t16 ==>|"100%"| t24
    t16 ==>|"44.4%"| t46
    t16 ==>|"44.4%"| t45
    t16 ==>|"44.3%"| t34
    t17 ==>|"47.3%"| t29
    t17 ==>|"40.1%"| t27
    t18 ==>|"100%"| t0
    t19 ==>|"85.2%"| t28
    t19 -->|"22.3%"| t23
    t19 -->|"10.3%"| t3
    t19 -->|"9.7%"| t15
    t19 -->|"9.2%"| t30
    t19 -.->|"0.23%"| t12
    t19 -.->|"0.23%"| t13
    t19 -.->|"0.23%"| t10
    t19 -.->|"0.22%"| t8
    t19 -.->|"0.22%"| t11
    t19 -.->|"0.19%"| t9
    t19 -.->|"0.0022%"| t14
    t20 ==>|"100%"| t25
    t20 ==>|"51.0%"| t3
    t20 ==>|"37.8%"| t15
    t20 ==>|"29.4%"| t23
    t20 -->|"24.4%"| t30
    t20 -.->|"0.23%"| t10
    t20 -.->|"0.23%"| t13
    t20 -.->|"0.23%"| t9
    t20 -.->|"0.22%"| t8
    t20 -.->|"0.21%"| t11
    t20 -.->|"0.21%"| t12
    t20 -.->|"0.0041%"| t14
    t21 ==>|"100%"| t2
    t21 ==>|"66.4%"| t30
    t21 ==>|"52.5%"| t15
    t21 ==>|"48.4%"| t23
    t21 ==>|"38.8%"| t3
    t21 -->|"14.8%"| t28
    t21 -.->|"0.075%"| t11
    t21 -.->|"0.075%"| t10
    t21 -.->|"0.073%"| t8
    t21 -.->|"0.072%"| t12
    t21 -.->|"0.069%"| t13
    t21 -.->|"0.068%"| t9
    t21 -.->|"0.0022%"| t14
    t22 ==>|"100%"| t16
    t22 ==>|"100%"| t19
    t22 ==>|"100%"| t20
    t22 ==>|"100%"| t21
    t23 ==>|"33.5%"| t7
    t23 -->|"23.1%"| t6
    t23 -->|"17.0%"| t4
    t23 -->|"14.1%"| t5
    t23 -.->|"3.2%"| t48
    t23 -.->|"2.6%"| t49
    t23 -.->|"1.2%"| t43
    t23 -.->|"1.2%"| t36
    t23 -.->|"1.1%"| t41
    t23 -.->|"0.84%"| t35
    t23 -.->|"0.72%"| t33
    t23 -.->|"0.56%"| t31
    t23 -.->|"0.41%"| t42
    t23 -.->|"0.17%"| t13
    t23 -.->|"0.17%"| t9
    t23 -.->|"0.1%"| t44
    t23 -.->|"0.066%"| t11
    t23 -.->|"0.064%"| t12
    t23 -.->|"0.061%"| t10
    t23 -.->|"0.06%"| t8
    t23 -.->|"0.0025%"| t50
    t23 -.->|"0.00041%"| t14
    t24 ==>|"87.0%"| t26
    t24 ==>|"86.7%"| t17
    t24 ==>|"75.1%"| t1
    t24 ==>|"37.7%"| t38
    t25 ==>|"60.2%"| t32
    t25 ==>|"41.8%"| t31
    t25 ==>|"30.8%"| t50
    t25 -->|"24.1%"| t49
    t25 -->|"22.4%"| t43
    t25 -->|"19.9%"| t42
    t25 -->|"18.1%"| t35
    t25 -->|"17.0%"| t44
    t25 -->|"15.9%"| t33
    t25 -->|"13.3%"| t48
    t25 -->|"12.8%"| t36
    t25 -->|"9.8%"| t41
    t26 ==>|"50.5%"| t27
    t26 ==>|"44.7%"| t39
    t26 ==>|"44.5%"| t40
    t26 ==>|"44.5%"| t47
    t26 ==>|"37.1%"| t29
    t26 -.->|"0.22%"| t12
    t26 -.->|"0.21%"| t11
    t26 -.->|"0.21%"| t13
    t26 -.->|"0.21%"| t10
    t26 -.->|"0.21%"| t8
    t26 -.->|"0.18%"| t9
    t26 -.->|"0.0031%"| t14
    t27 -.->|"0.05%"| t9
    t27 -.->|"0.048%"| t13
    t27 -.->|"0.0046%"| t11
    t27 -.->|"0.0043%"| t10
    t27 -.->|"0.0038%"| t12
    t27 -.->|"0.0031%"| t8
    t27 -.->|"0.00061%"| t14
    t28 ==>|"29.3%"| t32
    t28 -->|"24.4%"| t41
    t28 -->|"19.3%"| t36
    t28 -->|"17.5%"| t44
    t28 -->|"11.1%"| t48
    t28 -->|"10.9%"| t50
    t28 -->|"7.6%"| t42
    t28 -->|"7.4%"| t49
    t28 -->|"5.3%"| t35
    t28 -.->|"4.2%"| t43
    t28 -.->|"3.3%"| t31
    t28 -.->|"3.0%"| t33
    t33 -->|"7.4%"| t14
    t33 -.->|"0.0034%"| t9
    t33 -.->|"0.0026%"| t13
    t34 -->|"24.9%"| t1
    t34 -->|"13.3%"| t17
    t34 -->|"13.0%"| t26
    t34 -->|"5.5%"| t38
    t36 -->|"19.3%"| t10
    t36 -->|"17.5%"| t13
    t36 -->|"12.5%"| t12
    t36 -->|"11.2%"| t8
    t36 -->|"10.7%"| t11
    t36 -->|"10.6%"| t9
    t36 -->|"7.6%"| t14
    t37 -->|"23.3%"| t11
    t37 -->|"20.6%"| t8
    t37 -->|"19.3%"| t12
    t37 -->|"18.2%"| t9
    t37 -->|"15.8%"| t14
    t37 -->|"14.3%"| t10
    t37 -->|"12.8%"| t13
    t38 -->|"15.6%"| t29
    t38 -->|"9.4%"| t27
    t41 -->|"19.4%"| t10
    t41 -->|"17.9%"| t13
    t41 -->|"13.3%"| t12
    t41 -->|"11.3%"| t9
    t41 -->|"10.9%"| t8
    t41 -->|"10.5%"| t11
    t41 -->|"7.0%"| t14
    t42 -->|"22.3%"| t11
    t42 -->|"20.6%"| t8
    t42 -->|"20.4%"| t12
    t42 -->|"19.5%"| t9
    t42 -->|"15.7%"| t14
    t42 -->|"13.7%"| t13
    t42 -->|"13.3%"| t10
    t43 -->|"13.0%"| t14
    t44 -->|"21.4%"| t13
    t44 -->|"20.7%"| t9
    t44 -->|"16.0%"| t10
    t44 -->|"15.8%"| t12
    t44 -->|"15.6%"| t8
    t44 -->|"10.9%"| t14
    t44 -->|"10.7%"| t11
    t45 -.->|"0.15%"| t11
    t45 -.->|"0.15%"| t13
    t45 -.->|"0.15%"| t8
    t45 -.->|"0.15%"| t12
    t45 -.->|"0.14%"| t10
    t45 -.->|"0.13%"| t9
    t45 -.->|"0.0031%"| t14
    t48 -->|"13.4%"| t14
    t50 -->|"21.3%"| t11
    t50 -->|"20.0%"| t8
    t50 -->|"18.5%"| t9
    t50 -->|"17.5%"| t12
    t50 -->|"16.6%"| t10
    t50 -->|"15.6%"| t13
    t50 -->|"9.2%"| t14
```
