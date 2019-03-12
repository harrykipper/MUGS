# MUGS
Model of Urban Green Spaces. 

Modelling the emergence of inter-city differences in the usage of green space.

# Drivers of the dynamics
## Pull factors
### Culture

* Uniformly distribuited with means differing by social class.

### Neighbours’ behaviour (surroundings)

Observation of other’s behaviour. How to implement?

* “normative behaviors are influenced by relative shifts in observed behaviours”
** observe differences in the number of park-goers in local area from day to day (or week to week). Increase will encourage people to go, decrease will do nothing (or discourage).
* compare local behaviour against global (city)
** confront own area with rest of city, more park goers encourage people to go, less do nothing. (computationally less demanding, but less realistic)

## Push factors
### Dissonance (experience)

* class mix - as an homage to the homophily passion
* age mix - following Seaman et al.
* ethnic mix - not implemented (yet)

We assume that the extreme age groups (young and old) will be more sensitive to age differences, the others will be more sensitive to class differences.

Both evaluated against a tolerance parameter, uniformly distributed in the population.

* Should tolerance differ by age/class?

If too many (randomly selected) people in the park the same day are too different, dissonance increases, the person is discouraged to go again.

## Geography
* Areas of reference are postcode areas
* Population - an accurate reproduction in scale of Scottish cities (1/20 or 1/40).
** Age, gender, SEC.
*** Should include ethinicity/remove gender.
** Under 16/ Over 64 missing - will include.
* Agents randomly choose one among list of nearby parks.
** Bigger parks have a larger catchment area
* Introduce differences in scope by SEC?
** “Rich people will go further”?
