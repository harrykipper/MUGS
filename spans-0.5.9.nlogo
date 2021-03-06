extensions [csv table gis]

globals [
  version patch-dimension
  world place greenery walk ; GIS datasets
  zones visits-t parks parkT
  class-t dogs-t ind-file file-string area-file ppl-file picture
  classes quintiles prob-init
  factor ; proportion of people agents compare themselves to in the park.
  diversity ; Shannon idx
  sunny?
  urbs
  wst westend westenders
  dog-owners
  non-dog-owners
  parks-t
  conditions
  header-1
  header-1A
  header-ind
]

patches-own [simd name parkid parksize parkquality green? smallpark? centre attractivity walkability park-factor]

turtles-own [
  tol casa neigh myLocalParks closest-park myNeighbours
  prob-going gone-today gone-this-week visits
  age class gender ;  one day w'll have health, ethnicity, illnesses, tenure...
  has-dog
  Heter
]

to make-dogs-table
  ; Lookup table to assign the proportion of dog-owners for each class in each city (from SPANS)
  ; source of this is 'agents.csv'. The question is whether the last trip to nature included a dog.
  set dogs-t table:from-list
  (list
    (list "glasgow" (list 0.19 0.24 0.25 0.22))
    (list "edinburgh" (list 0.19 0.24 0.25 0.22))
    (list "dundee" (list 0.19 0.24 0.25 0.22))
    (list "aberdeen" (list 0.19 0.24 0.25 0.22))
  )
end

to setup
  ca
  file-close-all
  reset-ticks

  set header-1 "run,city,age,class,pull,random,segregated,heterophily,equalinit,initial-prob,walkability,a,b,tolerance,heteroph-tol,quality,dogs"
  set header-1A ",medAB,medC1,medC2,medDE,meanAB,meanC1,meanC2,meanDE,"
  set header-ind "sumAB,sumC1,sumC2,sumDE,"

  ; This is the west end of Glasgow.
  set wst ["S28000345" "S28000350" "S28000340" "S28000343" "S28000339" "S28000341"
    "S28000371" "S28000369" "S28000370" "S28000342" "S28000344"]

  ; certain combinations of cases don't make sense or produce trivial results
  ; if impossible-run [stop]

  set version "0.5.9"
  set classes [1 2 3 4]
  set quintiles [1 2 3 4 5]

  make-dogs-table

  set sunny? (ifelse-value
    city = "edinburgh" [0.89]
    city = "dundee"    [1]
                       [0.8] ; Glasgow / Aberdeen
  )

  set factor 10
  if scale <= 30 [set factor 20]

  setup-world

  ask patches [
    set simd 100
    set green? false
    set parksize 0
    set park-factor 0
  ]

  set visits-t table:make
  set diversity table:make

  ;; create a table that stores the exponent of the initial probability per class, and the colour of each class
  ; if not same-init-prob [set class-t table:from-list [[1 [1 yellow]] [2 [1.1 blue]] [3 [1.35 black]] [4 [1.85 red]]]]
  set class-t table:from-list [[1 [1.4 yellow]] [2 [1 blue]] [3 [1 red]] [4 [0.6 black]]]

  create-city-from-gis
  read-agents
  set zones filter [z -> count turtles with [neigh = z] > 0] zones
  set-preferred-parks
  ;if city = "glasgow" [set westenders turtles-on westend]

  if pull [ask turtles [identify-neighbours]]

  foreach zones [zn ->
    table:put visits-t zn [0 0]
    table:put diversity zn (getShannon zn)
  ]
  table:put visits-t "overall" [0 0]

  set prob-init table:make
  foreach classes [cl -> table:put prob-init cl mean [prob-going] of turtles with [class = cl]]

  set dog-owners turtles with [has-dog = true]
  set non-dog-owners turtles with [has-dog = false]

  if behaviorspace-run-number > 0 [prepare-data-save]  ;; If we are in batch mode we produce an output file with everything in it.
  colour-world
  ;vid:start-recorder
end

;; =============| Set up |====================

to read-agents
  let sex ["M" "F"]
  let agez [[16 19] [20 21] [22 24] [25 29] [30 34] [35 39] [40 44] [45 49] [50 54] [55 59] [60 64] [65 75]]
  let where city
  if edinburgh-test [
    set where "edinburgh"
    set random-allocation true
  ]
  let here urbs with [green? = false and is-string? name]
  let here-t table:group-agents here [name]
  foreach csv:from-file (word  "modeldata/socialclass1675-" where ".csv") [zn ->
    if table:has-key? here-t item 0 zn [
      let i 1
      let places table:get here-t item 0 zn
      if random-allocation [set places here]
      while [i < length zn] [
        foreach sex [sx ->
          foreach classes [cl ->
            foreach agez [ag ->
              let howmany round (item i zn / scale)
              if howmany > 0 [
                if complete-segregation [set places here with [simd = getSimd cl]]
                crt howmany [
                  set visits 0
                  move-to one-of places
                  set casa patch-here
                  set neigh [name] of casa
                  set myLocalParks []
                  set gender sx
                  set class cl
                  set has-dog false
                  if have-dogs? and random-float 1 <= item (class - 1) table:get dogs-t city [set has-dog true]
                  set Heter false
                  if class > 2 and random-float 1 < prop-heter-c2de [set Heter True]
                  set age item 0 ag + (random (1 + item 1 ag - item 0 ag))
                  set gone-this-week false
                  if behaviorspace-run-number = 0 [
                    set color item 1 table:get class-t class
                    set shape "circle"
                  ]
                  let inpro 0
                  ifelse same-init-prob
                  [set inpro (min list (160 - age) 100 / 100) * initial-prob]
                  [set inpro initial-prob * item 0 table:get class-t class]

                  set prob-going random-normal inpro 0.025
                  if prob-going < 0 [set prob-going 0.001]
                  set-diversity-thresholds
                ]
              ]
              set i i + 1
            ]
          ]
        ]
      ]
    ]
  ]
end

to setup-world
  ;; We scale the world according to the dimensions of the raster layer.
  ;; Our rasters are in meters and the pixel size is 5mt.
  gis:load-coordinate-system (word "modeldata/pcode-pop-" city ".prj")
  set world gis:load-dataset (word "modeldata/" city ".asc")
  set place gis:load-dataset (word "modeldata/pcode-pop-" city ".shp")
  set greenery gis:load-dataset (word "modeldata/" city "-city-parks.shp")
  set walk gis:load-dataset (word "modeldata/walk-" city ".shp")
  let x round gis:width-of world / scale
  let y round gis:height-of world / scale
  resize-world (x - 2 * x) x (y - 2 * y) y
  gis:set-world-envelope gis:envelope-of world

  ;; This tells us how much a patch measures in meters. A patch is (patch-dimension ^ 2) square meters.
  set patch-dimension round ((gis:width-of world * 5) / (max-pxcor * 2))

  ; https://stackoverflow.com/questions/24761104/netlogo-how-to-hatch-a-turtle-at-a-certain-distance-on-gis-layers
  ; We use this if we want to avoid scaling the world. In such case, all the values measured in patches have to be divided by patch-scale.
  ; set patch-scale (item 1 gis:world-envelope - item 0 gis:world-envelope ) / world-width ;/ scale
end

to create-parks
ask patches gis:intersecting greenery [
    if is-string? parkid [
      set green? true
      set parkid substring parkid 0 13  ;; The park identifier is uselessly long
    ]
  ]
  set parks-t table:group-agents patches with [green? = true] [parkid]
  set parkT table:make

  foreach table:keys parks-t [ pk ->
    let these table:get parks-t pk
    let howmany count these
    ifelse howmany > 5      ;; WARNING: Parks of 5 patches or less are disregarded. May or may not have an effect...
    [
      table:put parkT pk howmany
      let pkfctr ifelse-value howmany > (500 ^ 2) / (patch-dimension ^ 2) [2][1]
      ask these [
        set parksize howmany
        set park-factor pkfctr
        set smallpark? false
      ]
    ]
    [table:remove parks-t pk
      ask these [
        set green? false
        set parkid 0
        set parksize 0
      ]
    ]
  ]

  ; We now make a patchset of all parks. This increases simulation speed 2,500,000 times.
  set parks patches with [green? = true]

  let medsize median table:values parkT

  foreach table:keys parks-t [pk ->
    if have-quality [
      let these table:get parks-t pk ; with [parkid = pk]

      ; We define "small" a park of size below the median size of all parks in the city
      let small? table:get parkT pk <= medsize

      if small? [ask these [set smallpark? true]]
      let quality 4
      if small? and not any? these with [centre = 1] [
        set quality get-parkquality one-of modes [simd] of these
      ]
      ask these [set parkquality quality]

      ;; we now repurpose parkT as a table keeping track of what kind of people
      ;; visited each park through the simulation.
      ;; park-name | ab | c1 | c2 | de
    ]
    table:put parkT pk [0 0 0 0]
  ]
end

to assign-walkability
ask patches with [walkability > 0][
    set walkability (ifelse-value
      walkability = 1 [0.5]
      walkability = 2 [0.66]
      walkability = 3 [1]          ;; The walkability idx looks trustworthy only for the top quartile.
                      [2])
    if have-walkability = false [set walkability 1]
  ]
end

to create-city-from-gis
  if behaviorspace-run-number = 0 [gis:paint world 125]
  gis:set-drawing-color orange   ;; We keep these in behaviorspace to produce a good picture of the final state
  gis:draw place 2

  gis:apply-coverage place "CODE" name
  gis:apply-coverage place "QUINTILE" simd
  gis:apply-coverage place "CENTRE" centre
  gis:apply-coverage greenery "ID" parkid ;; "DISTNAME1" in the shp contains the human readable name of the park, but not all of them have it so we use "ID"
  gis:apply-coverage walk "WEIGHTEDQU" walkability

  create-parks
  assign-walkability
  set urbs patches with [walkability > 0]
  set zones remove-duplicates [name] of urbs with [is-string? name]
  if city = "glasgow" [
    ask patches with [name = "S28000373"][set simd 3]  ;; Dennistoun should be 3. Don't know why it isn't. Adjust manually
    ;set westend patches with [member? name wst]
  ]
end

to set-diversity-thresholds
  set tol tolerance
  ;set tol random-normal ((min list (155 - age) 100 / 100) * tol) 0.05 ;; Tolerance decreases with age. After 55 people get grumpy
  set tol random-normal tol 0.05
  if Heter = true and class > 2 [
    let tl heteroph-tol
    set tol random-normal tl 0.05
  ]
end

to set-preferred-parks
  ;; We assume that a park's "catchment area" is proportional to its size.
  ;; Agents will have a list of parks within their reach and one park as their closest.
  ;; We use the "closest park" information in one of our implementations of social influence.
  ask parks with [count neighbors with [not member? self parks] > 0] [
    set attractivity (get-attractivity parksize)
    ask turtles in-radius attractivity [  ; / patch-scale)
      ;if not member? [parkid] of myself myLocalParks
      set myLocalParks fput [parkid] of myself myLocalParks
    ]
  ]
;  show (word "DEBUG: " city ": " (count turtles with [length myLocalParks = 0] / count turtles) " agents with no parks!!")
  ask turtles [
    ;; If the agent doesn't have any park in their immediate reach the probability is minimized
    set myLocalParks remove-duplicates myLocalParks
    if length myLocalParks = 0 [set prob-going prob-going * 0.65]
    set closest-park [parkid] of min-one-of parks [distance myself]
    set myLocalParks remove closest-park myLocalParks ; closest park must appear only once
    set myLocalParks fput closest-park myLocalParks
  ]
end

to identify-neighbours
  ;; People of around my age within one class of my own in 500mt radius are "neighbours".
  set myNeighbours turtles in-radius (500 / patch-dimension) with [
    abs (age - [age] of myself) <= 5 and
    abs (class - [class] of myself) <= 1
  ]
end

; ===========| Main loop |=========================

to go
  ; if impossible-run [stop]  ;; Uncomment this only if running in BS with impossible combinations in the mix..
  ;vid:record-view
  ask turtles [
    move-to casa
    set gone-today false
  ]

  ; We update certain things on Sundays only, to save computing time
  if ticks > 0 and ticks mod 7 = 0 [
    update-visits-zone
    if pull and ticks > 7 [getLocalInfluence]
    if behaviorspace-run-number != 0 [save-individual-stats]
    ask turtles [
      set gone-this-week false
      (ifelse
        prob-going >= 1 [set prob-going 0.95]
        prob-going <= 0 [set prob-going 0.001]
      )
    ]
  ]

  ; if ticks = 14 [vid:save-recording (word "foo.mp4")]

  ;; The dog owner goes to a green space almost every day.
  ;; He will probably go to the closest available, regardless of quality and
  ;; of who else is there, deviating occasionally.
  ask dog-owners [
    let pr prob-going * walkability * sunny?
    let p ifelse-value pr < 0.33 [0.33][pr]
    if random-float 1 < p ;[
      ;ifelse length myLocalParks = 1 or random-float 1 < 0.7
      [go-outdoors first myLocalParks]
      ;[go-outdoors one-of but-first myLocalParks]
    ;]
  ]
  ;; The non dog owner goes to the first park in her list of accessible parks.
  ;; see evaluate-agents-experience for the rest of the dynamic.
  ask non-dog-owners [
    if random-float 1 < (prob-going * walkability * sunny?) [go-outdoors first myLocalParks]
  ]

  evaluate-agents-experience

  ;vid:record-view

  tick   ; a tick is a day
  if ticks = 1 + (years * 365) [
    if behaviorspace-run-number > 0 [
      export-view picture
      ask turtles [move-to casa]
      save-final-stats
    ]
    stop
  ]
end

to evaluate-agents-experience
  ;; All those who have gone to a park check whether they liked who else was there.
  ;; If an agent is dissonant, her likelihood to visit a park will decrease of factor 'a'
  ;; and will move the offending park to the bottom of the list of accessible parks,
  ;; so that next time he'll go to a different place.
  ;; If the mix was acceptable the likelihood of going again, and to the same park, goes up

  ;update-park-attendance pk people-here
  ;set visits-to-parks table:group-items parks [pk -> parkclass pk]

  foreach table:keys parks-t [pk ->
    let people-here turtles-on table:get parks-t pk ; with [parkid = pk]
    table:put parkT pk park-goers pk people-here
    if count people-here > 1 [
      ask people-here [
        ifelse iAmDissonant other people-here [parkquality] of patch-here
        [
          if length myLocalParks > 1 [set myLocalParks remove-item 0 lput pk myLocalParks]
          set prob-going prob-going - (a * prob-going)
        ]
        [set prob-going prob-going + (a * prob-going)]
      ]
    ]
  ]
end

to-report iAmDissonant [otherpeople pkq]

  ;; Here we check how different we are from the other people in the park, and how good the park is.
  ;; We don't consider everybody else, only a subset of other people, simulating random encounters.
  ;; Class and age differences are considered. Ethnic differences should probably also be included.
  ;; The assumption is that all agents are sensitive to class differences, elderly agents are also
  ;; sensitive to age differences.

  let fc factor * park-factor
  ; if [parksize] of patch-here > (1000 ^ 2) / (patch-dimension ^ 2) [set fc fc * 2] ;; we do this once in setup now...
  let others n-of (1 + (count otherpeople / fc)) otherpeople

  ;; We check the quality of the park ahead of everything, assuming that to be the primary concern of people.
  if have-quality and pkq = 0 [if random 100 < 80 [report true]]   ; If the park is bad (almost) everyone will hate it

  if age > 65 and push-age [if count others with [age <= 30] / count others > 0.7 [report true]]

  ;; In this implementation we assume that the top 2 classes (AB and C1)
  ;; are tolerant/intolerant towards people of the bottom two classes.
  ;; Some people from the bottom 2 classes seek to frequent parks where they are more likely
  ;; to encounter people from the top 2 classes.
  ;; In other words, the top 2 classes crave class segregation,
  ;; a fraction of people in the bottom 2 seek class diversity.

  ifelse class > 2 [
    ; the poor
    if have-quality and pkq < 4 [if random 100 < 35 [report true]]
    if push-cl [
      let differing count others with [class < 3] / count others
      ifelse Heter
      [if differing < tol [report true]] ;; this guy fancies being around the rich and is dissonant if there are too few.
      [if differing > tol [report true]] ;; this guy wants to be around similar people
    ]
    ][; the rich
    if have-quality and pkq < 4 [if random 100 < 65 [report true]]   ;; The rich have higher standards re. quality of parks
    if push-cl [
      let differing count others with [class > 2] / count others
      if differing > tol [report true]   ;; the rich always want to be among themselves.
    ]
  ]
  report false
end

;; ==========================|| "social influence" ||====================================

to getLocalInfluence
  ;; This checks a random neighbour. If they have gone more than us, we will be encouraged.
  ;; If they have gone much less than us, we will be discouraged.
  ask turtles [
    ;let ppl my-neighbours
    ;if global-perception [set ppl one-of other turtles]
    let influ b
    let quantovanno [visits] of one-of myNeighbours
    ifelse quantovanno >= (visits * 1.5)
    [set prob-going prob-going + (prob-going * a * influ)]
    [if quantovanno <= (visits * 0.5) [set prob-going prob-going - (prob-going * a * influ)]]
  ]
end

;; =============================================================================================
;; =============================================================================================

to go-outdoors [where]
  move-to one-of table:get parks-t where
  set visits visits + 1
  set gone-today true
  set gone-this-week true
end

;; =============================| Support functions |=====================================

to print-debug-info
  show (word city ": " count urbs with [not is-number? name] "; Agents: " count turtles)
  foreach table:keys class-t [
    cl -> let ppl turtles with [class = cl]
    print (word "Class " cl ": " count ppl "(" precision (count ppl / count turtles) 2 ") - median age: " median [age] of ppl)
    let allwalk remove-duplicates [walkability] of urbs
    foreach allwalk [wk ->
      let tot count ppl with [[walkability] of patch-here = wk]
      show (word "walkability " wk ": " tot " (" precision (tot / count ppl) 2 ")" )
    ]
    print ""
  ]
end

to showclasses
  foreach zones [zn ->
    let tonp turtles with [neigh = zn]
    foreach classes [cl -> show count tonp with [class = cl]
    ]
  ]
end

to-report impossible-run
  if (push-cl = false and pull = false and have-quality = false) or
     (random-allocation = true and complete-segregation = true) or
  (prop-heter-c2de = 0 and heteroph-tol > 0)
  [report true]
  report false
end

to colour-world
  ;ask patches [set pcolor blue]
  ;let patchcols table:from-list [[1 13] [2 red] [3 16] [4 17] [5 white]]
  ;ask patches with [simd > 0] [set pcolor table:get patchcols round simd]
  ask parks [set pcolor green]
end

to-report park-goers [park people-here]
  let old-count table:get parkT park
  report (map [ [classe prima] -> prima + count people-here with [class = classe] ]
    [1 2 3 4] old-count)
end

to update-visits-zone
  ;; Keep track of proportion of park goers per zone. We do this weekly
  foreach zones [z ->
    let old item 0 table:get visits-t z
    let locals turtles with [neigh = z]
    table:put visits-t z list (count locals with [gone-this-week] / count locals) old
  ]
  ;let old item 0 table:get visits-t "overall"
  ;table:put visits-t "overall" list mean (item 0 table:values visits-t) old
end

to-report get-parkquality [dep]
  if dep > 3 [ifelse random-float 1 < 0.66 [report 4][report 2]]
  ifelse dep > 1
  [ifelse random-float 1 < 0.66 [report 2][report 4]]
  [ifelse random-float 1 < 0.66 [report 0][report 2]]
end

to-report get-attractivity [pksize]
  ;; People will walk 200 meters to get to a park of 1,000sqm
  ;; and 2km to get to a park larger than 20,000sqm
  report (ifelse-value
    pksize < (200 ^ 2) / (patch-dimension ^ 2) [200 / patch-dimension]
      pksize < (500 ^ 2) / (patch-dimension ^ 2) [500 / patch-dimension]
      pksize < (1000 ^ 2) / (patch-dimension ^ 2)  [750 / patch-dimension]
      pksize < (1500 ^ 2) / (patch-dimension ^ 2) [1000 / patch-dimension][1350 / patch-dimension]
  )
end

;; Allocation of agents in the complete-segregation case
to-report getSimd [cl]
  report (ifelse-value
    cl = 1 [5]
    cl = 2 [3]
    cl = 3 [2]
           [1]
    )
end

to-report getShannon [zone]
  let tonp turtles with [neigh = zone]
  let div map
  [cl -> (1 + count tonp with [class = cl] / count tonp) * (ln (1 + count tonp with [class = cl] / count tonp))] classes
  report (- sum div)
end

to-report getShannonPk [park]
  let all table:get parkT park
  ifelse all != [0 0 0 0] [
    let div map
    [cl -> (1 + cl / sum all) * (ln (1 + cl / sum all))] all
    report (- sum div)
  ][report 0]
end

to-report get-freq [v]
  report (ifelse-value
    v >= 321 [3]
    v >= 270 [2]
    v >= 118 [1]
    v >= 37 [0]
    v >= 6 [-1]
    [-3]
    )
end

; ===================================| Data output |============================================

to prepare-data-save
  set conditions (word behaviorspace-run-number "," city "," push-age "," push-cl "," pull "," random-allocation ","
    complete-segregation "," prop-heter-c2de "," same-init-prob "," initial-prob "," have-walkability ","
    a "," b "," tolerance ","  heteroph-tol "," have-quality "," have-dogs? ",")
  let agepush ""
  let classpush ""
  let equalinit ""
  let influence ""
  let randomall ""
  let perfectseg ""
  let walkab ""
  if pull = true [set influence "-pull"]
  if push-cl = true [set classpush "-class"]
  if push-age = true [set agepush "-age"]
  if random-allocation = true [set randomall "_random"]
  if complete-segregation = true [set perfectseg "_segregated"]
  if same-init-prob [set equalinit "-equalinit"]
  if have-walkability [set walkab "-wlk"]
  set file-string (word version agepush classpush influence equalinit randomall perfectseg)
  let base (word "results/individual_runs/spans-" file-string "-p" initial-prob "-a" a "-b" b "-t"
    tolerance "-h" heteroph-tol "-pH" prop-heter-c2de walkab "-s" scale
  )

  let basename (word "results/individual_runs/spans-" version "-scale_" scale )

  set ppl-file word basename "-ppl.csv"
  set ind-file word basename "-ind.csv"
  set area-file word basename "-area.csv"
  set picture word base ".png"



  if not file-exists? ind-file [
    file-open ind-file
    file-print (word "tick," header-1 header-1A header-ind)
    file-close
  ]
  if not file-exists? area-file [
    file-open area-file
    file-print (word "tick," header-1 "," zones)
    file-close
  ]
end

to save-final-stats
  ;; This file contains the final values of every simulation run of a specific city.
  let dir "results/"
  let file-name (word dir "spans-" version "-scale_" scale "-all.csv")
  let zone-file (word dir "spans-" version "-scale_" scale "-zones.csv")
  let parks-file (word dir "spans-" version "-scale_" scale "-parks.csv")
  let header-2 "varAB,varC1,varC2,varDE,med1,med2,med3,med4,med5,mean1,mean2,mean3,mean4,mean5,mean,median"

  ifelse file-exists? file-name
  [file-open file-name]
  [
    file-open file-name
    file-type header-1
    file-type header-1A
    file-print header-2
  ]
  file-type conditions
  foreach classes [cls -> file-type (word (median [visits] of turtles with [class = cls] / years) ",")]
  foreach classes [cls -> file-type (word (mean [visits] of turtles with [class = cls] / years) ",")]
  foreach classes [cls ->
    let initial table:get prob-init cls
    ;file-type (word ((mean [prob-going] of turtles with [class = cls] - initial) / initial) ",")
    file-type (word (mean [prob-going] of turtles with [class = cls] / initial) ",")
  ]
  foreach quintiles [qtl ->
    ifelse count urbs with [simd = qtl] > 5  ;; we have to do this beacause some cities don't have all the deprivation quintiles
    [file-type (word (median [visits] of turtles with [[simd] of casa = qtl] / years) ",")]
    [file-type "NA,"]
  ]
  foreach quintiles [qtl ->
      ifelse count urbs with [simd = qtl] > 5
      [file-type (word (mean [visits] of turtles with [[simd] of casa = qtl] / years) ",")]
      [file-type "NA,"]
  ]
  file-type (word (mean [visits] of turtles / years) "," (median [visits] of turtles / years))
  file-print ""

;  if city = "glasgow" [
;    file-type (word "westend," but-first conditions)
;    foreach classes [cls -> file-type (word (median [visits] of westenders with [class = cls] / years) ",")]
;    foreach classes [cls -> file-type (word (mean [visits] of westenders with [class = cls] / years) ",")]
;    repeat 15 [file-type "NA,"]
;    file-print ""
;  ]

  file-close

  ifelse file-exists? zone-file
  [file-open zone-file]
  [
    file-open zone-file
    file-print (word "zone,diversity,ab,c1,c2,de," header-1 header-1A "median,mean")
  ]
  foreach zones [zn ->
    let all turtles with [neigh = zn]
    let ab count all with [class = 1] / count all
    let c1 count all with [class = 2] / count all
    let c2 count all with [class = 3] / count all
    let de count all with [class = 4] / count all
    file-type (word zn "," table:get diversity zn "," ab "," c1 "," c2 "," de "," conditions)
    foreach classes [cls ->
      let thisppl all with [class = cls]
      ifelse any? thisppl
      [file-type (word (median [visits] of thisppl / years) ",")]
      [file-type "NA,"]
    ]
    foreach classes [cls ->
      let thisppl all with [class = cls]
      ifelse any? thisppl
      [file-type (word (mean [visits] of thisppl / years) ",")]
      [file-type "NA,"]
    ]
    file-type (word (median [visits] of all / years) ",")
    file-type (word (mean [visits] of all / years) ",")
    file-print ""
  ]
  file-close

  ifelse file-exists? parks-file

  [file-open parks-file]
  [
    file-open parks-file
    file-print word header-1 ",park,ab,c1,c2,de,diversity"
  ]
  foreach table:keys parkT [pk ->
    let going table:get parkT pk
    file-type (word conditions pk "," item 0 going "," item 1 going "," item 2 going "," item 3 going "," getShannonPk pk)
    file-print ""
  ]
  file-close
  ifelse file-exists? parks-file
  [file-open ppl-file]
  [
    file-open ppl-file
    file-print "id,location,age,zone,ses,has.dog,visits,freq.to.park"
  ]
  ; "id,location,age,zone,ses,has.dog,visits,freq.to.park"
  ask turtles [file-print
    (word who "," city "," age "," simd "," class "," has-dog "," visits "," (get-freq (visits / years)))
  ]
  file-close
end

to save-individual-stats
  file-open ind-file
  file-type (word ticks "," conditions)
  foreach classes [cls -> file-type (word (median [visits] of turtles with [class = cls] / (ticks / 7)) ",")]
  foreach classes [cls ->
    let all turtles with [class = cls]
    file-type (word (count all with [gone-this-week] / count all) ",")
  ]
foreach classes [cls ->
    file-type (word (sum [visits] of turtles with [class = cls] / (ticks / 7)) "," )
  ]
  ;foreach classes [cls -> file-type (word (mean [visits] of turtles with [class = cls] / (ticks / 7)) ",")]
  file-print ""
  file-close
  file-open area-file
  file-type (word ticks ",")
  foreach zones [z -> file-type (word table:get visits-t z ",")]
  file-print ""
  file-close
end

to output-class-division
  file-open (word city "-class.csv")
  file-print "zone,ab,c1,c2,de,"
  foreach zones [zn ->
    file-type (word zn ",")
    foreach classes [cls -> file-type (word count turtles with [neigh = zn and class = cls] ",")]
    file-print ""
  ]
  file-close
end
@#$#@#$#@
GRAPHICS-WINDOW
255
10
2506
2150
-1
-1
6.25
1
1
1
1
1
0
0
0
1
-179
179
-170
170
0
0
1
day
25.0

BUTTON
196
87
251
120
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
196
122
251
155
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

SLIDER
4
10
193
43
initial-prob
initial-prob
0
0.2
0.07
0.001
1
NIL
HORIZONTAL

SLIDER
2
342
118
375
a
a
0
0.5
0.25
0.0001
1
NIL
HORIZONTAL

SLIDER
209
167
242
317
tolerance
tolerance
0
1
0.5
0.01
1
NIL
VERTICAL

INPUTBOX
202
10
252
70
years
4.0
1
0
Number

CHOOSER
97
83
189
128
scale
scale
5 8 10 20 30 40
2

SWITCH
3
165
169
198
same-init-prob
same-init-prob
0
1
-1000

CHOOSER
4
118
96
163
city
city
"aberdeen" "dundee" "edinburgh" "glasgow"
0

BUTTON
6
446
144
479
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
146
446
242
479
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
82
95
115
pull
pull
0
1
-1000

SWITCH
97
46
191
79
push-cl
push-cl
0
1
-1000

SWITCH
5
45
95
78
push-age
push-age
0
1
-1000

SWITCH
97
131
192
164
global-perception
global-perception
1
1
-1000

SWITCH
3
235
170
268
random-allocation
random-allocation
1
1
-1000

SWITCH
3
200
170
233
complete-segregation
complete-segregation
1
1
-1000

BUTTON
6
483
129
516
NIL
print-debug-info
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
3
271
169
304
have-walkability
have-walkability
0
1
-1000

SLIDER
173
167
206
317
heteroph-tol
heteroph-tol
0
1
0.5
0.01
1
NIL
VERTICAL

SWITCH
3
306
171
339
have-quality
have-quality
1
1
-1000

SLIDER
120
342
230
375
b
b
0
2
0.8
0.01
1
NIL
HORIZONTAL

SWITCH
6
518
157
551
edinburgh-test
edinburgh-test
1
1
-1000

SLIDER
2
378
181
411
prop-heter-c2de
prop-heter-c2de
0
1
0.33
0.01
1
NIL
HORIZONTAL

SWITCH
2
412
131
445
have-dogs?
have-dogs?
0
1
-1000

@#$#@#$#@
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
NetLogo 6.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="majority" repetitions="10" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 1 + (365 * years)</exitCondition>
    <enumeratedValueSet variable="tolerance">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heteroph-tol">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prop-heter-c2de">
      <value value="0.33"/>
      <value value="0.5"/>
      <value value="0.66"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-prob">
      <value value="0.07"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="b">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="same-init-prob">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="city">
      <value value="&quot;aberdeen&quot;"/>
      <value value="&quot;edinburgh&quot;"/>
      <value value="&quot;dundee&quot;"/>
      <value value="&quot;glasgow&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="scale">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pull">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-cl">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-age">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="global-perception">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-allocation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="complete-segregation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-walkability">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-quality">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-dogs?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="master" repetitions="10" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 1 + (365 * years)</exitCondition>
    <enumeratedValueSet variable="tolerance">
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heteroph-tol">
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prop-heter-c2de">
      <value value="0.33"/>
      <value value="0.5"/>
      <value value="0.66"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-prob">
      <value value="0.07"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="b">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="same-init-prob">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="city">
      <value value="&quot;aberdeen&quot;"/>
      <value value="&quot;edinburgh&quot;"/>
      <value value="&quot;dundee&quot;"/>
      <value value="&quot;glasgow&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="scale">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pull">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-cl">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-age">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="global-perception">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-allocation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="complete-segregation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-walkability">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-quality">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-dogs?">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="master-nullmodel" repetitions="10" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>ticks = 1 + (365 * years)</exitCondition>
    <enumeratedValueSet variable="tolerance">
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="heteroph-tol">
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.5"/>
      <value value="0.6"/>
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prop-heter-c2de">
      <value value="0.33"/>
      <value value="0.5"/>
      <value value="0.66"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-prob">
      <value value="0.07"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="b">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="same-init-prob">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="city">
      <value value="&quot;aberdeen&quot;"/>
      <value value="&quot;edinburgh&quot;"/>
      <value value="&quot;dundee&quot;"/>
      <value value="&quot;glasgow&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="scale">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pull">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-cl">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="push-age">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="global-perception">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-allocation">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="complete-segregation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-walkability">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-quality">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="have-dogs?">
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
