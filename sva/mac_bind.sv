// Attach assertions to every mac_array_4x4 instance (sees internal en/clr/acc and, for A9,
// the ctrl FSM state/row through hierarchical connections).
bind mac_array_4x4 mac_array_sva u_sva (.*, .state(u_ctrl.state), .row(u_ctrl.row));
