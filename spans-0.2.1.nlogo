extensions [csv table gis cf]

globals [
  version
  place greenery ; GIS datasets
  zones visits-t parks visits-to-parks
  class-t weekend attitudes summer winter
  ind-file area-file
  classes quintiles prob-init
]

patches-own [simd name weather parkid parksize green? attractivity here-this-week here-last-week]

turtles-own [
  tol casa local-parks closest-park
  prob-going prob-today gone-today gone-this-week visits
  id age ethni ethni2 health class gender ill tenure attitude has-car has-child has-dog work
]

to setup
  ca
  file-close-all
  reset-ticks
  set version "0.2.1"

  set classes [1 2 3 4]
  set quintiles [1 2 3 4 5]

  ask patches [
    set simd 100
    set green? false
    set parksize 0
  ]

  ; set place gis:load-dataset (word dir "../census/glasgow-city.shp")
  set place gis:load-dataset (word dir "modeldata/pcode-pop-" city ".shp")
  set greenery gis:load-dataset (word dir "modeldata/" city "-city-parks.shp")
  gis:set-world-envelope gis:envelope-of place

  set visits-t table:make
  ;set visits-to-parks table:make
;  foreach parks [pk ->
;    table:put visits-to-parks pk [0 0]
;  ]
  if not same-init-prob [set class-t table:from-list [[1 1] [2 1.1] [3 1.3] [4 1.5]]]  ; Class exponent for culture

  create-city-from-gis
  read-agents
  set-preferred-parks

  ask turtles [
    ifelse same-init-prob
    [set prob-going initial-prob]
    [
      let inpro initial-prob ^ table:get class-t class
      set prob-going random-normal inpro 0.025
      if prob-going < 0 [set prob-going 0.001]
    ]
  ]

  set prob-init table:make
  foreach classes [cl -> table:put prob-init cl mean [prob-going] of turtles with [class = cl]]

  ifelse behaviorspace-run-number = 0 [
    colour-agents
    colour-world
  ]
  [
    let agepush ""
    let classpush ""
    if push-cl = true [set classpush "-class"]
    if push-age = true [set agepush "-age"]
    set ind-file  (word dir "results/spans-" version "-" city "-parks-prob" initial-prob "-a" a "-tol" tolerance agepush classpush "-run" behaviorspace-run-number ".csv")
    set area-file (word dir "results/spans-" version "-" city "-parks-prob" initial-prob "-a" a "-tol" tolerance agepush classpush "-run" behaviorspace-run-number "-areas.csv")
    file-open ind-file
    file-print (word "tick,medAB,medC1,medC2,medDE,meanAB,meanC1,meanC2,meanDE,")
    file-close
    file-open area-file
    file-print (word "tick," zones)
    file-close
  ]

  ;vid:start-recorder
end

;; =============| Set up |====================

to read-agents
  let sex ["M" "F"]
  let agez [[16 19] [20 21] [22 24] [25 29] [30 34] [35 39] [40 44] [45 49] [50 54] [55 59] [60 64] [65 75]]
  foreach csv:from-file (word dir "modeldata/socialclass1675-" city ".csv") [zn ->
    let i 1
    while [i < length zn] [
      foreach sex [sx ->
        foreach classes [cl ->
          foreach agez [ag ->
            ; show (word "Processing zone:" item 0 zn "; sex:" sx "; class: " cl "; age group: " ag)
            let howmany round (item i zn / scale)
            let places patches with [name = item 0 zn and green? = false]
            if howmany > 0 and any? places [
              crt howmany [
                ;set shape "person"
                set visits 0
                if behaviorspace-run-number != 0 [set hidden? true]
                move-to one-of places
                set casa patch-here
                set local-parks []
                set gender sx
                set class cl
                set age item 0 ag + (random (1 + item 1 ag - item 0 ag))
                set gone-this-week false
                set has-dog false
                set tol random-normal tolerance 0.10
                if random 1 < 0.15 [set has-dog true]
                ;let locality patches in-radius 30 with [green?]
                ;set dist distance min-one-of locality [distance myself]
              ]
            ]
            set i i + 1
          ]
        ]
      ]
    ]
  ]
end

;; Maybe later
;to set-broad-ethni
;  ifelse (ethni = "Scottish" or ethni = "Other British" or ethni = "Irish") [set ethni2 "WB"][
;    ifelse (ethni = "African" or ethni = "Caribbean" or ethni = "Black") [set ethni2 "B"][
;      ifelse (ethni = "Indian" or ethni = "Pakistani" or ethni = "Arab" or ethni = "Bangladeshi") [set ethni2 "ME"][
;        ifelse (ethni = "Other White" or ethni = "Polish") [set ethni2 "EU"][set ethni2 "Other"]
;      ]
;    ]
;  ]
;end

to create-city-from-gis
  gis:apply-coverage place "CODE" name
  gis:apply-coverage place "QUINTILE" simd
  gis:apply-coverage greenery "ID" parkid    ;; "DISTNAME1" contains the name of the park, but not all of them have it. Use the ID for the moment
  ask patches gis:intersecting greenery [set green? true]
  set parks remove-duplicates [parkid] of patches with [green?]

  foreach parks [  ;; Each park patch knows how big the whole park is. Useful later, but maybe inefficient
    pk ->
    let pks patches with [green? and parkid = pk]
    let sz count pks
    ask pks [set parksize sz]
  ]

  ask patches with [green? and (parksize < 3 or is-number? parkid)] [
    set green? false
    set parkid 0
    set parksize 0
  ]

  if city = "glasgow" [ ask patches with [name = "S28000373"][set simd 3]]  ;; Dennistoun should be 3. Don't know why it isn't. Adjust manually
  set zones remove-duplicates [name] of patches with [is-string? name]
end

to set-preferred-parks
  ask patches with [green? and count neighbors with [green? = false] > 0] [
    set attractivity (get-attractivity parksize)
    ask turtles in-radius attractivity [
      if not member? [parkid] of myself local-parks [set local-parks fput [parkid] of myself local-parks]
    ]
  ]
  ask turtles [
    set closest-park [parkid] of min-one-of patches with [green?] [distance myself]
    if length local-parks = 0 [set local-parks fput closest-park local-parks]
  ]
end


; ===========| Main loop |=========================

to go
  set weekend false
  set summer false
  set winter false
  ; Summer
  ifelse ticks > 150 and ticks < 250 [
    set summer true
    ;ask patches [set weather weather * weather-bias]
  ]
  ;Winter
  [if (ticks >= 0 and ticks <= 90) or (ticks > 300) [
    set winter true
   ; ask patches [set weather weather * (1 / weather-bias)]
    ]
  ]

  ;vid:record-view
  ask turtles [
    move-to casa
    set gone-today false
  ]

  if ticks > 0 and (ticks mod 6 = 0 or ticks mod 7 = 0) [
    set weekend true

    ; We update things on Sundays
    if ticks mod 7 = 0 [
      update-visits
      ask turtles [
        if pull and ticks > 7 [update-feedbacks-week]
        set gone-this-week false
      ]
      ask patches with [green?] [
        set here-last-week here-this-week
        set here-this-week 0
      ]
      if behaviorspace-run-number != 0 [save-stuff]
    ]
  ]
  ;if ticks = 14 [vid:save-recording (word dir "/foo.mp4")]

  ask turtles [if random-float 1 < prob-going [go-outdoors]]

  ;let park-goers table:group-items parks [pk -> turtles-on patches with [parkid = pk]]

  foreach parks [pk ->
    let park patches with [parkid = pk]
    let people-here turtles-on park
    ;table:put visits-to-parks pk [(item 0 table:get visits-to-parks pk + count people-here) (item 1 table:get visits-to-parks pk)]
    ask park [set here-this-week here-this-week + count people-here]
    if count people-here > 1 [
      ;ask people-here [if iAmDissonant other people-here [set days-dissonant days-dissonant + 1]]
      ask people-here [if iAmDissonant other people-here [
        ; show (word "DEBUG: agent " who " of age " age ", class " class " is dissonant!!")
        set prob-going prob-going - (a * prob-going)]
        ; [show (word "DEBUG: agent " who " of age " age ", class " class " is NOT dissonant!!")]
      ]
    ]
  ]
  ;vid:record-view
  tick   ; a tick is a day

;  if ticks = 365 [
;    ask turtles [set age age + 1]
;
;    ;; Uncomment the following if we want agents to age and die
;
;   ; ifelse gender = "M"
;   ; [if random-float 1 <= table:get death-m age [die]]
;   ; [if random-float 1 <= table:get death-f age [die]]
;   ; ]
;  ]
  if ticks = years * 365 [
    if behaviorspace-run-number > 0 [save-final-stats]
    stop
  ]
end

to-report iAmDissonant [otherpeople]

  ;; Here we check how different we are from the other people in the park.
  ;; We don't consider everybody else, only a subset of other people, simulating random encounters.
  ;; Class and age differences are considered. Ethnic differences should probably also be included.
  ;; The assumption is that extreme age groups (young and old) are sensitive to age differences,
  ;; all the other age groups are sensitive to class differences.

  let others n-of (1 + (count otherpeople / 10)) otherpeople
  let differing 0

  ifelse age <= 20 or age >= 67
  [if push-age [set differing count others with [abs(age - [age] of myself) >= 45] / count others]]
  [if push-cl [set differing count others with [is-number? class and abs(class - [class] of myself) >= 2] / count others]]

  if differing > tol [report true]
  report false

end

;to update-feedbacks-week
;  let prop table:get visits-t [name] of casa
;  if prop > table:get visits-t "overall" [set prob-going prob-going + ((2 * a) * prob-going)]
;end

to update-feedbacks-week
  let pk one-of patches with [parkid = [closest-park] of myself]
  if [here-this-week] of pk > [here-last-week] of pk [set prob-going prob-going + ((2 * a) * prob-going)]
end

;to decide-activity
;
;; ========== static probabilities ===============
;  ;; Those with dogs probably go to the park every day
;  if has-dog [set prob-today random-normal 0.75 0.15]
;
;  ; The severely ill won't go out
;  if is-number? ill and ill = -2 [
;    ifelse age > 65 [set prob-today 0.001][set prob-today 0.003]
;  ]
;
;end

to go-outdoors
  let wheretogo one-of local-parks
  move-to one-of patches with [parkid = wheretogo]
  set visits visits + 1
  set gone-today true
  set gone-this-week true
end

;; =============================| Support functions |=====================================

to colour-agents
  let class-col table:from-list [[1 green] [2 blue] [3 grey] [4 0]]
  ask turtles [
    set color table:get class-col class
    ;if has-dog [set shape "x"]
  ]
end

to colour-world
  ;ask patches [set pcolor blue]
  let patchcols table:from-list [[1 13] [2 red] [3 16] [4 17] [5 white]]
  ask patches with [simd > 0] [set pcolor table:get patchcols round simd]
  ask patches with [green?][set pcolor green]
end

to update-visits
  ;; Keep track of proportion of park goers per zone.
  foreach zones [z ->
    let locals turtles-on patches with [name = z]
    table:put visits-t z (count locals with [gone-this-week] / count locals)
  ]
  table:put visits-t "overall" mean (table:values visits-t)
end

to-report get-attractivity [pksize]
  report (cf:ifelse-value
    pksize < 20 [5]
      pksize < 50 [10]
      pksize < 100 [15]
      pksize < 200 [25][35]
  )
end

to save-final-stats
  let file-name (word dir "results/spans-" version "-" city "-all.csv")
  ifelse file-exists? file-name
  [file-open file-name]
  [
    file-open file-name
    file-print "run,initial-prob,a,tolerance,sameprob,pull,push-class,push-age,varAB,varC1,varC2,varDE,medAB,medC1,medC2,medDE,meanAB,meanC1,meanC2,meanDE,med1,med2,med3,med4,med5,mean1,mean2,mean3,mean4,mean5,"
  ]
  file-type (word behaviorspace-run-number "," initial-prob "," a "," tolerance "," same-init-prob "," pull "," push-cl "," push-age ",")
  foreach classes [cls ->
    let initial table:get prob-init cls
    ;file-type (word ((mean [prob-going] of turtles with [class = cls] - initial) / initial) ",")
    file-type (word (mean [prob-going] of turtles with [class = cls] / initial) ",")
  ]
  foreach classes [cls -> file-type (word (median [visits] of turtles with [class = cls] / years) ",")]
  foreach classes [cls -> file-type (word (mean [visits] of turtles with [class = cls] / years) ",")]
  foreach quintiles [qtl -> file-type (word (median [visits] of turtles-on patches with [simd = qtl] / years) ",")]
  foreach quintiles [qtl -> file-type (word (mean [visits] of turtles-on patches with [simd = qtl] / years) ",")]
  file-print ""
  file-close
end

to save-stuff
  file-open ind-file
  file-type (word ticks ",")
  foreach classes [cls -> file-type (word (median [visits] of turtles with [class = cls] / (ticks / 7)) ",")]
  foreach classes [cls -> file-type (word (mean [visits] of turtles with [class = cls] / (ticks / 7)) ",")]
  file-print ""
  file-close
  file-open area-file
  file-type (word ticks ",")
  foreach zones [z -> file-type (word table:get visits-t z ",")]
  file-print ""
  file-close
end
@#$#@#$#@
GRAPHICS-WINDOW
437
10
1950
1024
-1
-1
5.0
1
7
1
1
1
0
0
0
1
-150
150
-100
100
0
0
1
day
30.0

BUTTON
8
526
81
559
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
83
526
146
559
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
6
10
428
260
mean visits
days
visits
0.0
700.0
0.0
0.0
true
true
"" ""
PENS
"AB" 1.0 0 -1184463 true "" "plot mean [visits] of turtles with [class = 1] / (ticks / 7)"
"C1" 1.0 0 -955883 true "" "plot mean [visits] of turtles with [class = 2] / (ticks / 7)"
"C2" 1.0 0 -9276814 true "" "plot mean [visits] of turtles with [class = 3] / (ticks / 7)"
"DE" 1.0 0 -16777216 true "" "plot mean [visits] of turtles with [class = 4] / (ticks / 7)"

PLOT
7
263
428
522
distribution of visits
visits
agents
0.0
365.0
0.0
20000.0
true
false
"set-plot-pen-mode 1\nset-histogram-num-bars 10" "histogram [visits] of turtles"
PENS
"default" 1.0 0 -16777216 true "" ""

SLIDER
4
732
151
765
initial-prob
initial-prob
0
0.2
0.1
0.001
1
NIL
HORIZONTAL

BUTTON
6
608
144
641
Display boundaries
ask patches with [\npcolor != blue and count neighbors with [\nname != [name] of myself] > 2 and \ncount neighbors with [pcolor = blue] = 0 ]\n[set pcolor black]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
4
810
319
870
dir
/home/stefano/ownCloud/sphsu/neigh/
1
0
String

SLIDER
153
732
291
765
a
a
0
1
0.03
0.0001
1
NIL
HORIZONTAL

SLIDER
294
733
429
766
tolerance
tolerance
0
1
0.41
0.01
1
NIL
HORIZONTAL

INPUTBOX
322
810
372
870
years
2.0
1
0
Number

CHOOSER
3
683
95
728
scale
scale
10 20 40 50
2

SWITCH
301
773
434
806
same-init-prob
same-init-prob
1
1
-1000

CHOOSER
97
684
235
729
city
city
"aberdeen" "dundee" "edinburgh" "glasgow"
3

TEXTBOX
6
653
156
683
EXPERIMENT SETUP ============
12
0.0
1

BUTTON
147
608
307
641
Display parks catchment
ask patches with [green? and count neighbors with [green? = false] > 0] [ask patches in-radius attractivity [set pcolor blue]]\nask patches with [green?][set pcolor green]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
309
609
433
642
Reset colours
ask patches [set pcolor black]\ncolour-world
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
5
775
95
808
pull
pull
0
1
-1000

SWITCH
98
775
192
808
push-cl
push-cl
0
1
-1000

TEXTBOX
8
575
158
605
INFO\n============
12
0.0
1

SWITCH
195
774
299
807
push-age
push-age
0
1
-1000

@#$#@#$#@
# Drivers of the dynamics

## Pull factors

### Culture

Uniformly distribuited with means differing by social class.

### Neighbours' behaviour (_surroundings_)

Observation of other's behaviour. How to implement?

- "_normative behaviors are influenced by relative shifts in observed behaviours_"
	- observe differences in the number of park-goers in local area from day to day (or week to week). Increase will encourage people to go, decrease will do nothing (or discourage).
- compare local behaviour against global (city)
	- confront own area with rest of city, more park goers encourage people to go, less do nothing.
		- (computationally less demanding, but less realistic) 

## Push factors

### Dissonance (_experience_)

- **class mix** - as an homage to the homophily passion
- **age mix** - following Seaman et al.
- **ethnic mix** - not implemented (yet)

We assume that the extreme age groups (young and old) will be more sensitive to age differences, the others will be more sensitive to class differences.

Both evaluated against a **tolerance** parameter, uniformly distributed in the population. 

- Should tolerance differ by age/class?

If too many (randomly selected) people in the park the same day are too different, **dissonance** increases, the person is discouraged to go again.

## Geography

- _Areas_ of reference are _postcode areas_
- Population - an accurate reproduction in scale of Scottish cities (1/20 or 1/40). 
	- Age, gender, SEC.
		- Should include ethinicity/remove gender.
	- Under 16/ Over 64 missing - will include.
- Agents randomly choose one among list of nearby parks.
	- Bigger parks have a larger catchment area
- Introduce differences in scope by SEC? 
	- "Rich people will go further"?


# Old model stuff. Don't read

The decision process is probabilistic. A baseline probability is adjusted considering the following:

* Weather
* Social class
* Weekend / weekday
* Age and health
* Employment status
* Presence of children / dogs.
* General attitude towards local green areas
* Distance from local green area
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <enumeratedValueSet variable="tolerance">
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-prob">
      <value value="0.06"/>
      <value value="0.12"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a">
      <value value="0.01"/>
      <value value="0.035"/>
      <value value="0.07"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="same-init-prob">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="city">
      <value value="&quot;glasgow&quot;"/>
      <value value="&quot;edinburgh&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pull">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-cl">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-age">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
