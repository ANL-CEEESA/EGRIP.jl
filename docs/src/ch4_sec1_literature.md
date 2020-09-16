# Literature Review
There are mainly five steps for power network restoration after a partial or full outage:
- Restoration time estimation
- Sectionalization
- Generator start-up optimization
- Path search
- Load pickup

The aforementioned problems have been studied in a separated manner. On the other hand, some researchers are focusing on solving the integrated problems. In addition, many factors such as dynamic security, black-start resource allocation, crew routing and transmission & distribution co-restoration have also been investigated. Here, we will have a brief review of current literature.

It is worth mentioning that there are already review papers on this topic:
- D. Lindenmeyer, H. W. Dommel, and M. M. Adibi, “Power system restoration - a bibliographical survey,” Int. J. Electr. Power Energy Syst., vol. 23, no. 3, pp. 219–227, 2001.
- Y. Liu, R. Fan, and V. Terzija, “Power system restoration: a literature review from 2006 to 2016,” J. Mod. Power Syst. Clean Energy, vol. 4, no. 3, pp. 332–341, 2016.

In addition, the following paper describes a holistic toolkit with different modules solving aforementioned restoration perspectives:
- Y. Hou, C. C. Liu, K. Sun, P. Zhang, S. Liu, and D. Mizumura, “Computation of milestones for decision support during system restoration,” IEEE Trans. Power Syst., vol. 26, no. 3, pp. 1399–1409, 2011.


## 1. Restoration time estimation
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| A. Assis Mota, L. T. M. Mota, and A. Morelato, “Visualization of power system restoration plans using CPM/PERT graphs,” IEEE Trans. Power Syst., vol. 22, no. 3, pp. 1322–1329, 2007. | ------------- | ----- |
| R. B. Duffey and T. Ha, “The probability and timing of power system restoration,” IEEE Trans. Power Syst., vol. 28, no. 1, pp. 3–9, 2013. | ------------- | ----- |

## 2. Sectionalization
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| J. J. Joglekar and Y. P. Nerkar, “A different approach in system restoration with special consideration of Islanding schemes,” Int. J. Electr. Power Energy Syst., vol. 30, no. 9, pp. 519–524, 2008. | ------------- | ----- |
| S. Nourizadeh, S. A. Nezam Sarmadi, M. J. Karimi, and A. M. Ranjbar, “Power system restoration planning based on Wide Area Measurement System,” Int. J. Electr. Power Energy Syst., vol. 43, no. 1, pp. 526–530, 2012. | ------------- | ----- |
| J. Quirós-Tortós, P. Wall, L. Ding, and V. Terzija, “Determination of sectionalising strategies for parallel power system restoration: A spectral clustering-based methodology,” Electr. Power Syst. Res., vol. 116, pp. 381–390, 2014. | ------------- | ----- |
| J. Quirós-Tortós, M. Panteli, P. Wall, and V. Terzija, “Sectionalising methodology for parallel system restoration based on graph theory,” IET Gener. Transm. Distrib., vol. 9, no. 11, pp. 1216–1225, 2015. | ------------- | ----- |
| L. Sun et al., “Network partitioning strategy for parallel power system restoration,” IET Gener. Transm. Distrib., vol. 10, no. 8, pp. 1883–1892, 2016. | ------------- | ----- |
|N. Ganganath, J. V. Wang, X. Xu, C. T. Cheng, and C. K. Tse, “Agglomerative clustering-based network partitioning for parallel power system restoration,” IEEE Trans. Ind. Informatics, vol. 14, no. 8, pp. 3325–3333, 2018.| ------------- | ----- |
| P. Demetriou, M. Asprou, and E. Kyriakides, “A real-time controlled islanding and restoration scheme based on estimated states,” IEEE Trans. Power Syst., vol. 34, no. 1, pp. 606–615, 2019. | ------------- | ----- |
| G. Patsakis, D. Rajan, I. Aravena, and S. Oren, “Strong Mixed-Integer Formulations for Power System Islanding and Restoration,” IEEE Trans. Power Syst., vol. 34, no. 6, pp. 4880–4888, 2019. | ------------- | ----- |
| J. Zhao et al., “Robust Distributed Coordination of Parallel Restored Subsystems in Wind Power Penetrated Transmission System,” IEEE Trans. Power Syst., vol. 8950, no. c, pp. 1–1, 2020. | ------------- | ----- |


## 3. Generator start-up optimization
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| W. Sun, C. C. Liu, and L. Zhang, “Optimal generator start-up strategy for bulk power system restoration,” IEEE Trans. Power Syst., vol. 26, no. 3, pp. 1357–1366, 2011. | ------------- | ----- |
| X. Gu, W. Liu, and C. Sun, “Optimisation for unit restarting sequence considering decreasing trend of unit start-up efficiency after a power system blackout,” IET Gener. Transm. Distrib., vol. 10, no. 16, pp. 4187–4196, 2016. | ------------- | ----- |
| Y. Zhao, Z. Lin, Y. Ding, Y. Liu, L. Sun, and Y. Yan, “A model predictive control based generator start-up optimization strategy for restoration with microgrids as black-start resources,” IEEE Trans. Power Syst., vol. 33, no. 6, pp. 7189–7203, 2018. | Motivation: microgrids as black-start resources and address uncertainty; Methood: MPC + scenario reduction using mass transportation problem; no power flow models | ----- |
| R. Sun, Y. Liu, and L. Wang, “An online generator start-up algorithm for transmission system self-healing based on mcts and sparse autoencoder,” IEEE Trans. Power Syst., vol. 34, no. 3, pp. 2061–2070, 2019. | Motivation: the shortcomings of offline restoration plan; Method: Expert system based online generator start-up system ==> Monte Carlo tree search and sparse autoencoder | Western Shandong Power Grid of China |
| X. Gu, G. Zhou, S. Li, and T. Liu, “Global optimisation model and algorithm for unit restarting sequence considering black-start zone partitioning,” IET Gener. Transm. Distrib., vol. 13, no. 13, pp. 2652–2663, 2019. | ------------- | ----- |
| L. Sun, W. Liu, C. Y. Chung, M. Ding, R. Bi, and L. Wang, “Improving the restorability of bulk power systems with the implementation of a wf-bess system,” IEEE Trans. Power Syst., vol. 34, no. 3, pp. 2366–2377, 2019. | Motivation: adtively dispatch wind and energy storage; Method: define restorability index ==> consider uncertainty and scenario reduction ==> optimal dispatch of wind and energy storage ==> Benders decomposition with restoration as master and dispatch as slave | Guangdong power system in China |
| L. Sun, Z. Lin, Y. Xu, F. Wen, C. Zhang, and Y. Xue, “Optimal Skeleton-Network Restoration Considering Generator Start-Up Sequence and Load Pickup,” IEEE Trans. Smart Grid, vol. 10, no. 3, pp. 3174–3185, 2019. | Motivation: integrate startup and transmission line selection; Method: sequentially solve three problems: generator startup, network building and load pickup | IEEE 39-bus; Guangdong power system in China |


## 4. Path search
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| Y. Liu and X. Gu, “Skeleton-network reconfiguration based on topological characteristics of scale-free networks and discrete particle swarm optimization,” IEEE Trans. Power Syst., vol. 22, no. 3, pp. 1267–1274, 2007. | ------------- | ----- |
| C. Wang, V. Vittal, V. S. Kolluri, and S. Mandal, “PTDF-based automatic restoration path selection,” IEEE Trans. Power Syst., vol. 25, no. 3, pp. 1686–1695, 2010. | ------------- | ----- |
|F. Edström and L. Söder, “On spectral graph theory in power system restoration,” IEEE PES Innov. Smart Grid Technol. Conf. Eur., 2011. | ------------- | ----- |
| W. Sun and C. C. Liu, “Optimal transmission path search in power system restoration,” Proc. IREP Symp. Bulk Power Syst. Dyn. Control - IX Optim. Secur. Control Emerg. Power Grid, IREP 2013, pp. 0–4, 2013. | ------------- | ----- |
| Y. Xie, K. Song, Q. Wu, and Q. Zhou, “Orthogonal genetic algorithm based power system restoration path optimization,” Int. Trans. Electr. Energy Syst., vol. 28, no. 12, pp. 1–17, 2018. | ------------- | ----- |
| S. Liao et al., “An improved two-stage optimization for network and load recovery during power system restoration,” Appl. Energy, vol. 249, no. January, pp. 265–275, 2019. | ------------- | ----- |
| S. Li, X. Gu, G. Zhou, and Y. Li, “Optimisation and comprehensive evaluation of alternative energising paths for power system restoration,” IET Gener. Transm. Distrib., vol. 13, no. 10, pp. 1923–1932, 2019. | ------------- | ----- |



## 5. Load pickup
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| Z. Qin, Y. Hou, C. C. Liu, S. Liu, and W. Sun, “Coordinating generation and load pickup during load restoration with discrete load increments and reserve constraints,” IET Gener. Transm. Distrib., vol. 9, no. 15, pp. 2437–2446, 2015. | ------------- | ----- |
| A. Gholami and F. Aminifar, “A Hierarchical Response-Based Approach to the Load Restoration Problem,” IEEE Trans. Smart Grid, vol. 8, no. 4, pp. 1700–1709, 2017. | ------------- | ----- |
| A. Golshani, W. Sun, and K. Sun, “Real-Time Optimized Load Recovery Considering Frequency Constraints,” IEEE Trans. Power Syst., vol. 34, no. 6, pp. 4204–4215, 2019. | ------------- | ----- |
| J. Zhao, H. Wang, Y. Liu, R. Azizipanah-Abarghooee, and V. Terzija, “Utility-oriented online load restoration considering wind power penetration,” IEEE Trans. Sustain. Energy, vol. 10, no. 2, pp. 706–717, 2019. | -------------------------- | -------- |
| J. Zhao, Y. Liu, H. Wang, and Q. Wu, “Receding horizon load restoration for coupled transmission and distribution system considering load-source uncertainty,” Int. J. Electr. Power Energy Syst., vol. 116, no. July 2019, p. 105517, 2020. | -------------------------- | -------- |
| J. Zhao, H. Wang, Q. Wu, N. D. Hatziargyriou, and F. Shen, “Distributed Risk-limiting Load Restoration for Wind Power Penetrated Bulk System,” IEEE Trans. Power Syst., vol. 8950, no. c, pp. 1–1, 2020. | -------------------------- | -------- |


## Integrated Methods
| **Paper** | **Technical Features** | **Test Systems** |
| -------------------------- | -------------------------- | -------- |
| Qiu, Feng, and Peijie Li. "An integrated approach for power system restoration planning." Proceedings of the IEEE 105, no. 7 (2017): 1234-1252. | *sequentially* integrated method: sectionalization==>optimize generator start-up==>path search==>solution refinement | IEEE 30-bus, IEEE 118-bus |
| A. Golshani, W. Sun, Q. Zhou, Q. P. Zheng, and J. Tong, “Two-Stage Adaptive Restoration Decision Support System for a Self-Healing Power Grid,” IEEE Trans. Ind. Informatics, vol. 13, no. 6, pp. 2802–2812, 2017. | -------------------------- | -------- |
| Y. Jiang et al., “Blackstart capability planning for power system restoration,” Int. J. Electr. Power Energy Syst., vol. 86, pp. 127–137, 2017. | -------------------------- | -------- |
| A. Golshani, W. Sun, Q. Zhou, Q. P. Zheng, J. Wang, and F. Qiu, “Coordination of Wind Farm and Pumped-Storage Hydro for a Self-Healing Power Grid,” IEEE Trans. Sustain. Energy, vol. 9, no. 4, pp. 1910–1920, 2018. | -------------------------- | -------- |
| A. Golshani, W. Sun, Q. Zhou, Q. P. Zheng, and Y. Hou, “Incorporating Wind Energy in Power System Restoration Planning,” IEEE Trans. Smart Grid, vol. 10, no. 1, pp. 16–28, 2019. | -------------------------- | -------- |
| W. Liu, J. Zhan, C. Y. Chung, and L. Sun, “Availability Assessment Based Case-Sensitive Power System Restoration Strategy,” IEEE Trans. Power Syst., vol. 35, no. 2, pp. 1432–1445, 2020. | -------------------------- | -------- |
