# The PowerModels Mathematical Model

As PowerModels implements a variety of power network optimization problems, the implementation is the best reference for precise mathematical formulations.  This section provides a complex number based mathematical specification for a prototypical AC Optimal Power Flow problem, to provide an overview of the typical mathematical models in PowerModels.
## Sets and Parameters

PowerModels implements a slightly generalized version of the AC Optimal Power Flow problem from [Matpower](http://www.pserc.cornell.edu/matpower/).  These generalizations make it possible for PowerModels to more accurately capture industrial transmission network datasets.  The core generalizations are,

- Support for multiple load ($S^d_k$) and shunt ($Y^s_{k}$) components on each bus $i$
- Line charging that supports a conductance and asymmetrical values ($Y^c_{ij}, Y^c_{ji}$)


```math
\begin{align}
%
\mbox{sets:} & \nonumber \\
& N \mbox{ - buses}\nonumber \\
& R \mbox{ - reference buses}\nonumber \\
& E, E^R \mbox{ - branches, forward and reverse orientation} \nonumber \\
& G, G_i \mbox{ - generators and generators at bus $i$} \nonumber \\
& L, L_i \mbox{ - loads and loads at bus $i$} \nonumber \\
& S, S_i \mbox{ - shunts and shunts at bus $i$} \nonumber \\
%
\mbox{data:} & \nonumber \\
& S^{gl}_k, S^{gu}_k \;\; \forall k \in G \nonumber \mbox{ - generator complex power bounds}\\
& c_{2k}, c_{1k}, c_{0k} \;\; \forall k \in G \nonumber  \mbox{ - generator cost components}\\
& v^l_i, v^u_i \;\; \forall i \in N \nonumber \mbox{ - voltage bounds}\\
& S^d_k \;\; \forall k \in L \nonumber \mbox{ - load complex power consumption}\\
& Y^s_{k} \;\; \forall k \in S \nonumber \mbox{ - bus shunt admittance}\\
& Y_{ij}, Y^c_{ij}, Y^c_{ji} \;\; \forall (i,j) \in E \nonumber \mbox{ - branch pi-section parameters}\\
& {T}_{ij} \;\; \forall (i,j) \in E \nonumber \mbox{ - branch complex transformation ratio}\\
& s^u_{ij}  \;\; \forall (i,j) \in E \nonumber \mbox{ - branch apparent power limit}\\
& i^u_{ij}  \;\; \forall (i,j) \in E \nonumber \mbox{ - branch current limit}\\
& \theta^{\Delta l}_{ij}, \theta^{\Delta u}_{ij} \;\; \forall (i,j) \in E \nonumber \mbox{ - branch voltage angle difference bounds}\\
%
\end{align}
```

## AC Optimal Power Flow

A complete mathematical model is as follows,

```math
\begin{align}
%
\mbox{variables: } & \nonumber \\
& S^g_k \;\; \forall k\in G \mbox{ - generator complex power dispatch} \label{var_generation}\\
& V_i \;\; \forall i\in N \label{var_voltage} \mbox{ - bus complex voltage}\\
& S_{ij} \;\; \forall (i,j) \in E \cup E^R  \label{var_complex_power} \mbox{ - branch complex power flow}\\
%
\mbox{minimize: } & \sum_{k \in G} c_{2k} (\Re(S^g_k))^2 + c_{1k}\Re(S^g_k) + c_{0k} \label{eq_objective}\\
%
\mbox{subject to: } & \nonumber \\
& \angle V_{r} = 0  \;\; \forall r \in R \label{eq_ref_bus}\\
& S^{gl}_k \leq S^g_k \leq S^{gu}_k \;\; \forall k \in G  \label{eq_gen_bounds}\\
& v^l_i \leq |V_i| \leq v^u_i \;\; \forall i \in N \label{eq_voltage_bounds}\\
& \sum_{\substack{k \in G_i}} S^g_k - \sum_{\substack{k \in L_i}} S^d_k - \sum_{\substack{k \in S_i}} (Y^s_k)^* |V_i|^2 = \sum_{\substack{(i,j)\in E_i \cup E_i^R}} S_{ij} \;\; \forall i\in N \label{eq_kcl_shunt} \\
& S_{ij} = \left( Y_{ij} + Y^c_{ij}\right)^* \frac{|V_i|^2}{|{T}_{ij}|^2} - Y^*_{ij} \frac{V_i V^*_j}{{T}_{ij}} \;\; \forall (i,j)\in E \label{eq_power_from}\\
& S_{ji} = \left( Y_{ij} + Y^c_{ji} \right)^* |V_j|^2 - Y^*_{ij} \frac{V^*_i V_j}{{T}^*_{ij}} \;\; \forall (i,j)\in E \label{eq_power_to}\\
& |S_{ij}| \leq s^u_{ij} \;\; \forall (i,j) \in E \cup E^R \label{eq_thermal_limit}\\
& |I_{ij}| \leq i^u_{ij} \;\; \forall (i,j) \in E \cup E^R \label{eq_current_limit}\\
& \theta^{\Delta l}_{ij} \leq \angle (V_i V^*_j) \leq \theta^{\Delta u}_{ij} \;\; \forall (i,j) \in E \label{eq_angle_difference}
%
\end{align}
```

Note that for clarity of this presentation some model variants that PowerModels supports have been omitted (e.g. piecewise linear cost functions and HVDC lines).  Details about these variants is available in the [Matpower](http://www.pserc.cornell.edu/matpower/) documentation.


### Mapping to function names
- Eq. $\eqref{var_generation}$ - variable_gen_power
- Eq. $\eqref{var_voltage}$ - variable_bus_voltage
- Eq. $\eqref{var_complex_power}$ - variable_branch_power
- Eq. $\eqref{eq_objective}$ -
- Eq. $\eqref{eq_ref_bus}$ -
- Eq. $\eqref{eq_gen_bounds}$ -
- Eq. $\eqref{eq_voltage_bounds}$ -
- Eq. $\eqref{eq_kcl_shunt}$ -
- Eq. $\eqref{eq_power_from}$ -
- Eq. $\eqref{eq_power_to}$ -
- Eq. $\eqref{eq_thermal_limit}$ -
- Eq. $\eqref{eq_current_limit}$ - 
- Eq. $\eqref{eq_angle_difference}$ -
