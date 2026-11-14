//  Copyright (C) 2026 Rodimus
// Based on MAME kangaroo.cpp (Ville Laitinen, Aaron Giles, BSD-3-Clause)

module kangaroo_dispatcher
(
    input                reset,
    input                clk_10m,

    input          [4:0] in0,              // {coin_r, coin_l, start2, start1, service}
    input          [7:0] in1,              // {3'b0, punch, down, up, left, right} P1
    input          [7:0] in2,              // {punch, down, up, left, right} P2
    input          [7:0] dsw0,

    output               video_hsync, video_vsync,
    output               video_hblank, video_vblank,
    output               ce_pix,

    input          [3:0] h_center,
    input          [2:0] v_center,
    output         [7:0] video_r, video_g, video_b,

    output signed [15:0] sound_l,
    output signed [15:0] sound_r,

    input         [24:0] ioctl_addr,
    input          [7:0] ioctl_data,
    input                ioctl_wr,
    input          [7:0] ioctl_index,

    input                pause,
    input                crt_flip,

    input                mcu_present,

    input         [15:0] hs_address,
    input          [7:0] hs_data_in,
    output         [7:0] hs_data_out,
    input                hs_write
);

wire rom0_cs, rom1_cs, rom2_cs, rom3_cs, rom4_cs, rom5_cs;
wire idx0_wr = ioctl_wr & (ioctl_index == 8'd0);
selector main_sel
(
    .ioctl_addr(ioctl_addr),
    .rom0_cs(rom0_cs), .rom1_cs(rom1_cs), .rom2_cs(rom2_cs),
    .rom3_cs(rom3_cs), .rom4_cs(rom4_cs), .rom5_cs(rom5_cs)
);

wire sndrom_cs = (ioctl_index == 8'd1);
wire idx1_wr = ioctl_wr & sndrom_cs;

wire idx6_wr = ioctl_wr & (ioctl_index == 8'd6);

wire blit0_cs, blit1_cs, blit2_cs, blit3_cs;
wire idx2_wr = ioctl_wr & (ioctl_index == 8'd2);
blit_selector blit_sel
(
    .ioctl_addr(ioctl_addr),
    .blit0_cs(blit0_cs), .blit1_cs(blit1_cs),
    .blit2_cs(blit2_cs), .blit3_cs(blit3_cs)
);

/////////////////////////////  Shared CPU / MCU / sound chip pool  /////////////////////////////
chip_pool_pkg::z80r_i_t z80_0_i, z80_1_i;
chip_pool_pkg::z80r_o_t z80_0_o, z80_1_o;
chip_pool_pkg::mb88_i_t mb88_0_i;
chip_pool_pkg::mb88_o_t mb88_0_o;
chip_pool_pkg::ayr_i_t  ay_0_i;
chip_pool_pkg::ay_o_t   ay_0_o;

t80sv_T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_0
(
    .RESET_n(z80_0_i.reset_n), .CLK(clk_10m), .CEN(z80_0_i.ce), .INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_0_o.m1_n), .MREQ_n(z80_0_o.mreq_n), .IORQ_n(z80_0_o.iorq_n), .RD_n(z80_0_o.rd_n), .WR_n(z80_0_o.wr_n),
    .RFSH_n(z80_0_o.rfsh_n), .A(z80_0_o.a), .DI(z80_0_i.di), .DO(z80_0_o.dout)
);

t80sv_T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_1
(
    .RESET_n(z80_1_i.reset_n), .CLK(clk_10m), .CEN(z80_1_i.ce), .INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_1_o.m1_n), .MREQ_n(z80_1_o.mreq_n), .IORQ_n(z80_1_o.iorq_n), .RD_n(z80_1_o.rd_n), .WR_n(z80_1_o.wr_n),
    .RFSH_n(z80_1_o.rfsh_n), .A(z80_1_o.a), .DI(z80_1_i.di), .DO(z80_1_o.dout)
);

wire [3:0] mcu_r0, mcu_r1, mcu_r2, mcu_r3, mcu_ol, mcu_oh;
assign mb88_0_o.r_out = {mcu_r3, mcu_r2, mcu_r1, mcu_r0};
assign mb88_0_o.o     = {mcu_oh, mcu_ol};
mb88 mb88_0
(
    .clock(clk_10m), .ena(mb88_0_i.ena), .reset_n(mb88_0_i.reset_n), .ram_clr(1'b0),
    .r0_port_in(mb88_0_i.r_in[3:0]), .r1_port_in(mb88_0_i.r_in[7:4]), .r2_port_in(mb88_0_i.r_in[11:8]), .r3_port_in(mb88_0_i.r_in[15:12]),
    .r0_port_out(mcu_r0), .r1_port_out(mcu_r1), .r2_port_out(mcu_r2), .r3_port_out(mcu_r3),
    .k_port_in(mb88_0_i.k), .ol_port_out(mcu_ol), .oh_port_out(mcu_oh), .p_port_out(mb88_0_o.p), .o_wr(mb88_0_o.o_wr),
    .stby_n(1'b1), .tc_n(mb88_0_i.tc_n), .irq_n(mb88_0_i.irq_n), .sc_in_n(1'b1), .si_n(mb88_0_i.si_n),
    .sc_out_n(), .so_n(), .to_n(),
    .rom_addr(mb88_0_o.rom_a), .rom_data(mb88_0_i.rom_d)
);

jt49_bus #(.COMP(3'b010)) ay_0
(
    .rst_n(ay_0_i.rst_n), .clk(clk_10m), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1), .din(ay_0_i.din), .sel(1'b1),
    .dout(ay_0_o.dout), .sound(ay_0_o.sound), .A(ay_0_o.a), .B(ay_0_o.b), .C(ay_0_o.c), .sample(),
    .IOA_in(ay_0_i.ioa_in), .IOA_out(), .IOB_in(ay_0_i.iob_in), .IOB_out(ay_0_o.iob_out)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [11:0] rom_cpu_a, snd_rom_a;
wire [13:0] blitrom_a;
wire [10:0] mcu_prog_a, mcu_prot_a;
wire  [7:0] rom0_d, rom1_d, rom2_d, rom3_d, rom4_d, rom5_d, blit0_d, blit1_d, blit2_d, blit3_d;
wire  [7:0] blitrom_d, mcu_prog_d, mcu_prot_d, snd_rom_d;

eprom_4k rom0 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom0_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom0_cs & idx0_wr), .WR(ioctl_wr));
eprom_4k rom1 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom1_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom1_cs & idx0_wr), .WR(ioctl_wr));
eprom_4k rom2 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom2_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom2_cs & idx0_wr), .WR(ioctl_wr));
eprom_4k rom3 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom3_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom3_cs & idx0_wr), .WR(ioctl_wr));
eprom_4k rom4 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom4_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom4_cs & idx0_wr), .WR(ioctl_wr));
eprom_4k rom5 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(rom5_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(rom5_cs & idx0_wr), .WR(ioctl_wr));

eprom_4k blit0 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(blit0_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(blit0_cs & idx2_wr), .WR(ioctl_wr));
eprom_4k blit1 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(blit1_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(blit1_cs & idx2_wr), .WR(ioctl_wr));
eprom_4k blit2 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(blit2_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(blit2_cs & idx2_wr), .WR(ioctl_wr));
eprom_4k blit3 (.ADDR(rom_cpu_a), .CLK(clk_10m), .DATA(blit3_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(blit3_cs & idx2_wr), .WR(ioctl_wr));

wire blit0_wr = blit0_cs & idx2_wr, blit1_wr = blit1_cs & idx2_wr, blit2_wr = blit2_cs & idx2_wr, blit3_wr = blit3_cs & idx2_wr;
wire [13:0] blitrom_dl_addr = blit0_wr ? {2'b00, ioctl_addr[11:0]} :
                               blit1_wr ? {2'b01, ioctl_addr[11:0]} :
                               blit2_wr ? {2'b10, ioctl_addr[11:0]} :
                               blit3_wr ? {2'b11, ioctl_addr[11:0]} :
                               14'd0;
wire blitrom_dl_wr = ioctl_wr & (blit0_wr | blit1_wr | blit2_wr | blit3_wr);
dpram_dc #(.widthad_a(14), .width_a(8)) blitrom_mem
(
    .clock_a(clk_10m), .address_a(blitrom_a), .data_a(8'd0), .wren_a(1'b0), .q_a(blitrom_d),
    .clock_b(clk_10m), .address_b(blitrom_dl_addr), .data_b(ioctl_data), .wren_b(blitrom_dl_wr), .q_b()
);

dpram_dc #(.widthad_a(11), .width_a(8)) mcu_prog
(
    .clock_a(clk_10m), .address_a(mcu_prog_a), .data_a(8'd0), .wren_a(1'b0), .q_a(mcu_prog_d),
    .clock_b(clk_10m), .address_b(ioctl_addr[10:0]), .data_b(ioctl_data), .wren_b(idx6_wr & ~ioctl_addr[11]), .q_b()
);
dpram_dc #(.widthad_a(11), .width_a(8)) mcu_prot
(
    .clock_a(clk_10m), .address_a(mcu_prot_a), .data_a(8'd0), .wren_a(1'b0), .q_a(mcu_prot_d),
    .clock_b(clk_10m), .address_b(ioctl_addr[10:0]), .data_b(ioctl_data), .wren_b(idx6_wr & ioctl_addr[11]), .q_b()
);

eprom_4k sndrom (.ADDR(snd_rom_a), .CLK(clk_10m), .DATA(snd_rom_d), .ADDR_DL(ioctl_addr), .CLK_DL(clk_10m), .DATA_IN(ioctl_data), .CS_DL(sndrom_cs), .WR(idx1_wr));

/////////////////////////////  Board RAM pool  /////////////////////////////
//   pr 0  1K   work RAM E000 (port B hiscore)
//   pr 1-8 16K VRAM byte lanes: lo [7:0] / [15:8], hi [7:0] / [15:8], and the plane-B scanout mirrors lo2 / hi2
//              (every VRAM write is a whole 16-bit word, so a lane pair is exactly the old 16-bit RAM)
ram_pool_pkg::pram_i_t [8:0] pr_i;
ram_pool_pkg::pram_o_t [8:0] pr_o;
ram_pool_pkg::pram_i_t       sp_i;
ram_pool_pkg::pram_o_t       sp_o;

dpram_dc #(.widthad_a(10)) pr_0
(
    .clock_a(clk_10m), .address_a(pr_i[0].a_addr[9:0]), .data_a(pr_i[0].a_d), .wren_a(pr_i[0].a_we), .q_a(pr_o[0].a_q),
    .clock_b(clk_10m), .address_b(pr_i[0].b_addr[9:0]), .data_b(pr_i[0].b_d), .wren_b(pr_i[0].b_we), .q_b(pr_o[0].b_q)
);
dpram_dc #(.widthad_a(14)) pr_1
(
    .clock_a(clk_10m), .address_a(pr_i[1].a_addr[13:0]), .data_a(pr_i[1].a_d), .wren_a(pr_i[1].a_we), .q_a(pr_o[1].a_q),
    .clock_b(clk_10m), .address_b(pr_i[1].b_addr[13:0]), .data_b(pr_i[1].b_d), .wren_b(pr_i[1].b_we), .q_b(pr_o[1].b_q)
);
dpram_dc #(.widthad_a(14)) pr_2
(
    .clock_a(clk_10m), .address_a(pr_i[2].a_addr[13:0]), .data_a(pr_i[2].a_d), .wren_a(pr_i[2].a_we), .q_a(pr_o[2].a_q),
    .clock_b(clk_10m), .address_b(pr_i[2].b_addr[13:0]), .data_b(pr_i[2].b_d), .wren_b(pr_i[2].b_we), .q_b(pr_o[2].b_q)
);
dpram_dc #(.widthad_a(14)) pr_3
(
    .clock_a(clk_10m), .address_a(pr_i[3].a_addr[13:0]), .data_a(pr_i[3].a_d), .wren_a(pr_i[3].a_we), .q_a(pr_o[3].a_q),
    .clock_b(clk_10m), .address_b(pr_i[3].b_addr[13:0]), .data_b(pr_i[3].b_d), .wren_b(pr_i[3].b_we), .q_b(pr_o[3].b_q)
);
dpram_dc #(.widthad_a(14)) pr_4
(
    .clock_a(clk_10m), .address_a(pr_i[4].a_addr[13:0]), .data_a(pr_i[4].a_d), .wren_a(pr_i[4].a_we), .q_a(pr_o[4].a_q),
    .clock_b(clk_10m), .address_b(pr_i[4].b_addr[13:0]), .data_b(pr_i[4].b_d), .wren_b(pr_i[4].b_we), .q_b(pr_o[4].b_q)
);
dpram_dc #(.widthad_a(14)) pr_5
(
    .clock_a(clk_10m), .address_a(pr_i[5].a_addr[13:0]), .data_a(pr_i[5].a_d), .wren_a(pr_i[5].a_we), .q_a(pr_o[5].a_q),
    .clock_b(clk_10m), .address_b(pr_i[5].b_addr[13:0]), .data_b(pr_i[5].b_d), .wren_b(pr_i[5].b_we), .q_b(pr_o[5].b_q)
);
dpram_dc #(.widthad_a(14)) pr_6
(
    .clock_a(clk_10m), .address_a(pr_i[6].a_addr[13:0]), .data_a(pr_i[6].a_d), .wren_a(pr_i[6].a_we), .q_a(pr_o[6].a_q),
    .clock_b(clk_10m), .address_b(pr_i[6].b_addr[13:0]), .data_b(pr_i[6].b_d), .wren_b(pr_i[6].b_we), .q_b(pr_o[6].b_q)
);
dpram_dc #(.widthad_a(14)) pr_7
(
    .clock_a(clk_10m), .address_a(pr_i[7].a_addr[13:0]), .data_a(pr_i[7].a_d), .wren_a(pr_i[7].a_we), .q_a(pr_o[7].a_q),
    .clock_b(clk_10m), .address_b(pr_i[7].b_addr[13:0]), .data_b(pr_i[7].b_d), .wren_b(pr_i[7].b_we), .q_b(pr_o[7].b_q)
);
dpram_dc #(.widthad_a(14)) pr_8
(
    .clock_a(clk_10m), .address_a(pr_i[8].a_addr[13:0]), .data_a(pr_i[8].a_d), .wren_a(pr_i[8].a_we), .q_a(pr_o[8].a_q),
    .clock_b(clk_10m), .address_b(pr_i[8].b_addr[13:0]), .data_b(pr_i[8].b_d), .wren_b(pr_i[8].b_we), .q_b(pr_o[8].b_q)
);
dpram_dc #(.widthad_a(10)) sp_0
(
    .clock_a(clk_10m), .address_a(sp_i.a_addr[9:0]), .data_a(sp_i.a_d), .wren_a(sp_i.a_we), .q_a(sp_o.a_q),
    .clock_b(clk_10m)
);
assign sp_o.b_q = 8'd0;

wire [7:0] cpu_sound_latch;
wire       cpu_sound_latch_wr;
wire [2:0] raw_r, raw_g;
wire [1:0] raw_b;

Kangaroo_CPU cpu_board
(
    .reset(reset),
    .clk_10m(clk_10m),

    .video_r(raw_r),
    .video_g(raw_g),
    .video_b(raw_b),
    .video_hsync(video_hsync),
    .video_vsync(video_vsync),
    .video_hblank(video_hblank),
    .video_vblank(video_vblank),
    .ce_pix(ce_pix),

    .h_center(h_center),
    .v_center(v_center),

    .dsw0(dsw0),
    .in0(in0),
    .in1(in1),
    .in2(in2),

    .sound_latch(cpu_sound_latch),
    .sound_latch_wr(cpu_sound_latch_wr),

    .mcu_present(mcu_present),

    .pause(pause),
    .crt_flip(crt_flip),

    .hs_address(hs_address),
    .hs_data_in(hs_data_in),
    .hs_data_out(hs_data_out),
    .hs_write(hs_write),

    .z80_0_i(z80_0_i), .z80_0_o(z80_0_o), .mb88_0_i(mb88_0_i), .mb88_0_o(mb88_0_o),
    .rom_cpu_a(rom_cpu_a), .rom0_d(rom0_d), .rom1_d(rom1_d), .rom2_d(rom2_d), .rom3_d(rom3_d), .rom4_d(rom4_d),
    .rom5_d(rom5_d), .blit0_d(blit0_d), .blit1_d(blit1_d), .blit2_d(blit2_d), .blit3_d(blit3_d),
    .blitrom_a(blitrom_a), .blitrom_d(blitrom_d), .mcu_prog_a(mcu_prog_a), .mcu_prog_d(mcu_prog_d),
    .mcu_prot_a(mcu_prot_a), .mcu_prot_d(mcu_prot_d),
    .pr_i(pr_i), .pr_o(pr_o)
);

wire signed [15:0] snd_mono;

Kangaroo_SND snd_board
(
    .reset(reset),
    .clk_10m(clk_10m),

    .sound_latch(cpu_sound_latch),
    .sound_latch_wr(cpu_sound_latch_wr),

    .vblank(video_vblank),

    .sound_out(snd_mono),

    .pause(pause),

    .z80_1_i(z80_1_i), .z80_1_o(z80_1_o), .ay_0_i(ay_0_i), .ay_0_o(ay_0_o),
    .snd_rom_a(snd_rom_a), .snd_rom_d(snd_rom_d), .sp_i(sp_i), .sp_o(sp_o)
);

assign sound_l = snd_mono;
assign sound_r = snd_mono;

assign video_r = {raw_r, raw_r, raw_r[2:1]};
assign video_g = {raw_g, raw_g, raw_g[2:1]};
assign video_b = {raw_b, raw_b, raw_b, raw_b};

endmodule
