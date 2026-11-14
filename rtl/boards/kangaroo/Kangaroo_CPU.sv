// Based on MAME kangaroo.cpp (Ville Laitinen, Aaron Giles, BSD-3-Clause)

module Kangaroo_CPU
(
    input         reset,
    input         clk_10m,

    output  [2:0] video_r, video_g,
    output  [1:0] video_b,
    output        video_hsync, video_vsync,
    output        video_hblank, video_vblank,
    output        ce_pix,

    input   [3:0] h_center,
    input   [2:0] v_center,

    input   [7:0] dsw0,
    input   [4:0] in0,
    input   [7:0] in1,
    input   [7:0] in2,

    output  [7:0] sound_latch,
    output        sound_latch_wr,

    input         mcu_present,    // 1 = MB8841 fitted (kangaroo/kangarooa); 0 = bootleg / Funky Fish

    input         pause,
    input         crt_flip,

    input  [15:0] hs_address,
    input   [7:0] hs_data_in,
    output  [7:0] hs_data_out,
    input         hs_write,

    output chip_pool_pkg::z80r_i_t z80_0_i,
    input  chip_pool_pkg::z80r_o_t z80_0_o,
    output chip_pool_pkg::mb88_i_t mb88_0_i,
    input  chip_pool_pkg::mb88_o_t mb88_0_o,

    output [11:0] rom_cpu_a,
    input   [7:0] rom0_d, rom1_d, rom2_d, rom3_d, rom4_d, rom5_d,
    input   [7:0] blit0_d, blit1_d, blit2_d, blit3_d,
    output [13:0] blitrom_a,
    input   [7:0] blitrom_d,
    output [10:0] mcu_prog_a,
    input   [7:0] mcu_prog_d,
    output [10:0] mcu_prot_a,
    input   [7:0] mcu_prot_d,

    output ram_pool_pkg::pram_i_t [8:0] pr_i,
    input  ram_pool_pkg::pram_o_t [8:0] pr_o
);

reg [1:0] div = 2'd0;
always_ff @(posedge clk_10m) begin
    div <= div + 2'd1;
end
wire cen_5m  = (div[0] == 1'b0);
wire cen_2m5 = (div == 2'd0);

assign ce_pix = cen_5m;

wire [15:0] cpu_A;
wire  [7:0] cpu_Dout;
wire n_m1, n_mreq, n_iorq, n_rd, n_wr, n_rfsh;

assign n_m1 = z80_0_o.m1_n; assign n_mreq = z80_0_o.mreq_n; assign n_iorq = z80_0_o.iorq_n;
assign n_rd = z80_0_o.rd_n; assign n_wr = z80_0_o.wr_n; assign n_rfsh = z80_0_o.rfsh_n;
assign cpu_A = z80_0_o.a; assign cpu_Dout = z80_0_o.dout;

wire mem_access = ~n_mreq & n_rfsh;

wire cs_rom = mem_access & (cpu_A[15:14] == 2'b00) & ~cpu_A[13];
wire cs_rom_hi = mem_access & (cpu_A[15:13] == 3'b001);
wire cs_rom_top = mem_access & (cpu_A[15:13] == 3'b010);
wire cs_any_rom = cs_rom | cs_rom_hi | cs_rom_top;

wire cs_videoram = mem_access & (cpu_A[15:14] == 2'b10);

wire cs_blitbank = mem_access & (cpu_A[15:13] == 3'b110);

wire cs_workram = mem_access & (cpu_A[15:10] == 6'b111000);

wire cs_dsw = mem_access & (cpu_A[15:10] == 6'b111001);

wire cs_vidctrl = mem_access & (cpu_A[15:10] == 6'b111010);

wire cs_in0 = mem_access & (cpu_A[15:8] == 8'hEC);

wire cs_in1 = mem_access & (cpu_A[15:8] == 8'hED);

wire cs_in2 = mem_access & (cpu_A[15:8] == 8'hEE);

wire cs_mcu = mem_access & (cpu_A[15:8] == 8'hEF);

wire [7:0] rom_D;
wire [7:0] blitbank_D;
wire [7:0] workram_D;
wire [7:0] mcu_dout;

wire [7:0] cpu_Din =
    cs_any_rom     ? rom_D :
    cs_blitbank    ? blitbank_D :
    (cs_workram & ~n_rd) ? workram_D :
    cs_dsw         ? dsw0 :
    cs_in0         ? {3'b000, in0} :
    cs_in1         ? in1 :
    cs_in2         ? in2 :
    cs_mcu         ? mcu_dout :
    8'hFF;

wire [7:0] rom0_D, rom1_D, rom2_D, rom3_D, rom4_D, rom5_D;

assign rom_D = (cpu_A[15:12] == 4'h0) ? rom0_D :
               (cpu_A[15:12] == 4'h1) ? rom1_D :
               (cpu_A[15:12] == 4'h2) ? rom2_D :
               (cpu_A[15:12] == 4'h3) ? rom3_D :
               (cpu_A[15:12] == 4'h4) ? rom4_D :
               (cpu_A[15:12] == 4'h5) ? rom5_D :
               8'hFF;

assign rom_cpu_a = cpu_A[11:0];
assign rom0_D = rom0_d;
assign rom1_D = rom1_d;
assign rom2_D = rom2_d;
assign rom3_D = rom3_d;
assign rom4_D = rom4_d;
assign rom5_D = rom5_d;

wire [7:0] blit0_D, blit1_D, blit2_D, blit3_D;
wire blit_bank_hi = (video_control[8] & 8'h05) == 0;

assign blitbank_D = cpu_A[12] ?
    (blit_bank_hi ? blit3_D : blit1_D) :
    (blit_bank_hi ? blit2_D : blit0_D);

assign blit0_D = blit0_d;
assign blit1_D = blit1_d;
assign blit2_D = blit2_d;
assign blit3_D = blit3_d;

assign pr_i[0].a_addr = {6'd0, cpu_A[9:0]}; assign pr_i[0].a_d = cpu_Dout; assign pr_i[0].a_we = cs_workram & ~n_wr;
assign pr_i[0].b_addr = {6'd0, hs_address[9:0]}; assign pr_i[0].b_d = hs_data_in; assign pr_i[0].b_we = hs_write;
assign workram_D = pr_o[0].a_q;
assign hs_data_out = pr_o[0].b_q;

reg [7:0] video_control [0:10];
integer vc_i;
initial begin
    for (vc_i = 0; vc_i < 11; vc_i = vc_i + 1)
        video_control[vc_i] = 8'd0;
end

reg blitter_start = 0;

always_ff @(posedge clk_10m) begin
    blitter_start <= 0;
    if(cs_vidctrl & ~n_wr) begin
        if(cpu_A[3:0] <= 4'd10)
            video_control[cpu_A[3:0]] <= cpu_Dout;
        if(cpu_A[3:0] == 4'd5)
            blitter_start <= 1;
    end
end

reg [7:0] slatch = 8'd0;
reg       slatch_wr_pulse = 0;
always_ff @(posedge clk_10m) begin
    slatch_wr_pulse <= 0;
    if(cs_in0 & ~n_wr) begin
        slatch <= cpu_Dout;
        slatch_wr_pulse <= 1;
    end
end
assign sound_latch = slatch;
assign sound_latch_wr = slatch_wr_pulse;

reg [7:0] nmi_boot_cnt = 8'd0;
reg n_nmi_boot = 1'b1;
always_ff @(posedge clk_10m) begin
    if(!reset) begin
        nmi_boot_cnt <= 8'd255;
        n_nmi_boot <= 1'b1;
    end
    else if(nmi_boot_cnt > 0 && cen_2m5) begin
        nmi_boot_cnt <= nmi_boot_cnt - 8'd1;
        if(nmi_boot_cnt == 8'd32)
            n_nmi_boot <= 1'b0;
        else if(nmi_boot_cnt == 8'd16)
            n_nmi_boot <= 1'b1;
    end
end

wire n_nmi = mcu_present ? mcu_nmi_n : n_nmi_boot;

localparam int MCU_CEN_DIV = 6;
reg [2:0] mcu_div_cnt = 3'd0;
always @(posedge clk_10m)
    if (cen_2m5) mcu_div_cnt <= (mcu_div_cnt == MCU_CEN_DIV[2:0] - 3'd1) ? 3'd0 : mcu_div_cnt + 3'd1;
wire mcu_ena       = cen_2m5 & ~pause & (mcu_div_cnt == MCU_CEN_DIV[2:0] - 3'd1);
wire mcu_reset_n   = reset & mcu_present;

wire [10:0] mcu_rom_addr;
wire  [7:0] mcu_rom_q;
wire  [3:0] mcu_ol, mcu_oh;
wire  [7:0] mcu_o = {mcu_oh, mcu_ol};
wire  [3:0] r0_out, r1_out, r2_out, r3_out;

reg  [7:0] main_data = 8'd0;
always_ff @(posedge clk_10m)
    if (cs_mcu & ~n_wr) main_data <= cpu_Dout;

wire [10:0] protrom_addr = {2'b00, r3_out[1], mcu_o};
wire  [7:0] protrom_q;

wire  [3:0] mcu_k = 4'hF
                  & ( r2_out[0] ? main_data[3:0] : 4'hF)
                  & (~r3_out[0] ? protrom_q[3:0] : 4'hF);

wire mcu_nmi_n = ~r3_out[3];
assign mcu_dout = mcu_present ? {4'h0, r0_out} : 8'h00;

assign {r0_out, r1_out, r2_out, r3_out} = {mb88_0_o.r_out[3:0], mb88_0_o.r_out[7:4], mb88_0_o.r_out[11:8], mb88_0_o.r_out[15:12]};
assign {mcu_oh, mcu_ol} = mb88_0_o.o;
assign mcu_rom_addr = mb88_0_o.rom_a;

assign mcu_prog_a = mcu_rom_addr;
assign mcu_rom_q = mcu_prog_d;

assign mcu_prot_a = protrom_addr;
assign protrom_q = mcu_prot_d;

reg n_irq = 1'b1;
reg vblank_last = 0;
always_ff @(posedge clk_10m) begin
    if(!reset) begin
        n_irq <= 1'b1;
        vblank_last <= 0;
    end
    else begin
        vblank_last <= video_vblank;
        if(video_vblank & ~vblank_last)
            n_irq <= 1'b0;
        if(~n_m1 & ~n_iorq)
            n_irq <= 1'b1;
    end
end

reg [9:0] h_cnt = 10'd0;
reg [8:0] v_cnt = 9'd0;

always_ff @(posedge clk_10m) begin
    if(!reset) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end
    else begin
        if(h_cnt == 10'd639) begin
            h_cnt <= 0;
            if(v_cnt == 9'd259)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 9'd1;
        end
        else
            h_cnt <= h_cnt + 10'd1;
    end
end

wire video_hblank_raw = (h_cnt >= 10'd512);
wire [9:0] hs_start = 10'd536 + {{5{h_center[3]}}, h_center, 1'b0};
wire [9:0] hs_end   = hs_start + 10'd48;
wire video_hsync_raw  = (h_cnt >= hs_start) & (h_cnt < hs_end);
reg [1:0] hblank_sr = 2'b11;
reg [1:0] hsync_sr  = 2'b00;
always_ff @(posedge clk_10m) begin
    hblank_sr <= {hblank_sr[0], video_hblank_raw};
    hsync_sr  <= {hsync_sr[0],  video_hsync_raw};
end
assign video_hblank = hblank_sr[1];
assign video_hsync  = hsync_sr[1];
assign video_vblank = (v_cnt < 9'd8) | (v_cnt >= 9'd248);
// the 4-line pulse must start in 248..255: base 252 + 3-bit two's complement offset
wire [8:0] vs_start = 9'd252 + {{6{v_center[2]}}, v_center};
wire [8:0] vs_end   = vs_start + 9'd4;
assign video_vsync  = (v_cnt >= vs_start) & (v_cnt < vs_end);

wire [15:0] vram_lo_qa, vram_hi_qa;
wire [15:0] vram_lo_qb, vram_hi_qb;
reg  [13:0] vram_addr_a;
reg  [15:0] vram_lo_da, vram_hi_da;
reg         vram_we_a;
wire [13:0] vram_addr_b;

assign pr_i[1].a_addr = {2'd0, vram_addr_a}; assign pr_i[1].a_d = vram_lo_da[7:0]; assign pr_i[1].a_we = vram_we_a;
assign pr_i[1].b_addr = {2'd0, vram_addr_b}; assign pr_i[1].b_d = 8'd0; assign pr_i[1].b_we = 1'b0;
assign pr_i[2].a_addr = {2'd0, vram_addr_a}; assign pr_i[2].a_d = vram_lo_da[15:8]; assign pr_i[2].a_we = vram_we_a;
assign pr_i[2].b_addr = {2'd0, vram_addr_b}; assign pr_i[2].b_d = 8'd0; assign pr_i[2].b_we = 1'b0;
assign vram_lo_qa = {pr_o[2].a_q, pr_o[1].a_q};
assign vram_lo_qb = {pr_o[2].b_q, pr_o[1].b_q};

assign pr_i[3].a_addr = {2'd0, vram_addr_a}; assign pr_i[3].a_d = vram_hi_da[7:0]; assign pr_i[3].a_we = vram_we_a;
assign pr_i[3].b_addr = {2'd0, vram_addr_b}; assign pr_i[3].b_d = 8'd0; assign pr_i[3].b_we = 1'b0;
assign pr_i[4].a_addr = {2'd0, vram_addr_a}; assign pr_i[4].a_d = vram_hi_da[15:8]; assign pr_i[4].a_we = vram_we_a;
assign pr_i[4].b_addr = {2'd0, vram_addr_b}; assign pr_i[4].b_d = 8'd0; assign pr_i[4].b_we = 1'b0;
assign vram_hi_qa = {pr_o[4].a_q, pr_o[3].a_q};
assign vram_hi_qb = {pr_o[4].b_q, pr_o[3].b_q};

wire [15:0] vram2_lo_qb, vram2_hi_qb;
wire [13:0] vram_addr_b2;

assign pr_i[5].a_addr = {2'd0, vram_addr_a}; assign pr_i[5].a_d = vram_lo_da[7:0]; assign pr_i[5].a_we = vram_we_a;
assign pr_i[5].b_addr = {2'd0, vram_addr_b2}; assign pr_i[5].b_d = 8'd0; assign pr_i[5].b_we = 1'b0;
assign pr_i[6].a_addr = {2'd0, vram_addr_a}; assign pr_i[6].a_d = vram_lo_da[15:8]; assign pr_i[6].a_we = vram_we_a;
assign pr_i[6].b_addr = {2'd0, vram_addr_b2}; assign pr_i[6].b_d = 8'd0; assign pr_i[6].b_we = 1'b0;
assign vram2_lo_qb = {pr_o[6].b_q, pr_o[5].b_q};
assign pr_i[7].a_addr = {2'd0, vram_addr_a}; assign pr_i[7].a_d = vram_hi_da[7:0]; assign pr_i[7].a_we = vram_we_a;
assign pr_i[7].b_addr = {2'd0, vram_addr_b2}; assign pr_i[7].b_d = 8'd0; assign pr_i[7].b_we = 1'b0;
assign pr_i[8].a_addr = {2'd0, vram_addr_a}; assign pr_i[8].a_d = vram_hi_da[15:8]; assign pr_i[8].a_we = vram_we_a;
assign pr_i[8].b_addr = {2'd0, vram_addr_b2}; assign pr_i[8].b_d = 8'd0; assign pr_i[8].b_we = 1'b0;
assign vram2_hi_qb = {pr_o[8].b_q, pr_o[7].b_q};

function [31:0] expand_data;
    input [7:0] data;
    reg [31:0] e;
    begin
        e = 32'd0;
        if (data[0]) e = e | 32'h00000055;
        if (data[4]) e = e | 32'h000000aa;
        if (data[1]) e = e | 32'h00005500;
        if (data[5]) e = e | 32'h0000aa00;
        if (data[2]) e = e | 32'h00550000;
        if (data[6]) e = e | 32'h00aa0000;
        if (data[3]) e = e | 32'h55000000;
        if (data[7]) e = e | 32'haa000000;
        expand_data = e;
    end
endfunction

function [31:0] build_layermask;
    input [3:0] mask;
    reg [31:0] m;
    begin
        m = 32'd0;
        if (mask[3]) m = m | 32'h30303030;
        if (mask[2]) m = m | 32'hc0c0c0c0;
        if (mask[1]) m = m | 32'h03030303;
        if (mask[0]) m = m | 32'h0c0c0c0c;
        build_layermask = m;
    end
endfunction

wire [7:0] blitrom_qa;
reg  [13:0] blitrom_addr_a;

assign blitrom_a = blitrom_addr_a;
assign blitrom_qa = blitrom_d;

localparam ST_IDLE        = 4'd0;
localparam ST_CPU_RMW_RD  = 4'd1;
localparam ST_CPU_RMW_WR  = 4'd2;
localparam ST_BLIT_SETUP  = 4'd3;
localparam ST_BLIT_ROMRD  = 4'd4;
localparam ST_BLIT_RMW_RD = 4'd5;
localparam ST_BLIT_RMW_WR_LO = 4'd6;
localparam ST_BLIT_RMW_RD2   = 4'd7;
localparam ST_BLIT_RMW_WR_HI = 4'd8;
localparam ST_BLIT_NEXT   = 4'd9;
localparam ST_CPU_RMW_RD2 = 4'd10;
localparam ST_BLIT_ROWSTART = 4'd11;
localparam ST_BLIT_WAIT_LO  = 4'd12;
localparam ST_BLIT_WAIT_HI  = 4'd13;

reg [3:0]  vram_state = ST_IDLE;
reg [7:0]  blit_width;
reg [7:0]  blit_height;
reg [7:0]  blit_x_cnt;
reg [7:0]  blit_y_cnt;
reg [15:0] blit_cur_src;
reg [15:0] blit_cur_dst;
reg [7:0]  blit_adj_mask;
reg        blit_pend = 0;
reg [7:0]  pend_w, pend_h, pend_mask;
reg [15:0] pend_src, pend_dst;
reg [7:0]  blit_rom_data_lo;
reg [7:0]  blit_rom_data_hi;

reg [13:0] cpu_wr_addr;
reg [7:0]  cpu_wr_data;
reg [3:0]  cpu_wr_mask;

reg [31:0] rmw_old_word;
reg [31:0] rmw_new_word;
reg [31:0] rmw_expdata;
reg [31:0] rmw_layermask;

always_ff @(posedge clk_10m) begin
    if (!reset) begin
        vram_state <= ST_IDLE;
        vram_we_a <= 0;
    end
    else begin
        vram_we_a <= 0;

        if (blitter_start && vram_state != ST_IDLE) begin
            blit_pend <= 1'b1;
            pend_w    <= video_control[4];
            pend_h    <= video_control[5];
            pend_src  <= {video_control[1], video_control[0]};
            pend_dst  <= {video_control[3], video_control[2]};
            pend_mask <= video_control[8];
        end

        case (vram_state)
            ST_IDLE: begin
                if (blitter_start || blit_pend) begin
                    blit_width   <= blitter_start ? video_control[4] : pend_w;
                    blit_height  <= blitter_start ? video_control[5] : pend_h;
                    blit_cur_src <= blitter_start ? {video_control[1], video_control[0]} : pend_src;
                    blit_cur_dst <= blitter_start ? {video_control[3], video_control[2]} : pend_dst;
                    blit_x_cnt  <= 0;
                    blit_y_cnt  <= 0;
                    blit_adj_mask <= blitter_start ? video_control[8] : pend_mask;
                    if (!blitter_start) blit_pend <= 1'b0;
                    vram_state <= ST_BLIT_SETUP;
                end
                else if (cs_videoram & ~n_wr) begin
                    cpu_wr_addr <= cpu_A[13:0];
                    cpu_wr_data <= cpu_Dout;
                    cpu_wr_mask <= video_control[8][3:0];
                    vram_addr_a <= cpu_A[13:0];
                    vram_state <= ST_CPU_RMW_RD;
                end
            end

            ST_CPU_RMW_RD: begin
                rmw_expdata  <= expand_data(cpu_wr_data);
                rmw_layermask <= build_layermask(cpu_wr_mask);
                vram_state <= ST_CPU_RMW_RD2;
            end

            ST_CPU_RMW_RD2: begin
                rmw_old_word <= {vram_hi_qa, vram_lo_qa};
                vram_state <= ST_CPU_RMW_WR;
            end

            ST_CPU_RMW_WR: begin
                rmw_new_word = (rmw_old_word & ~rmw_layermask) | (rmw_expdata & rmw_layermask);
                vram_addr_a <= cpu_wr_addr;
                vram_lo_da <= rmw_new_word[15:0];
                vram_hi_da <= rmw_new_word[31:16];
                vram_we_a  <= 1;
                vram_state <= ST_IDLE;
            end

            ST_BLIT_SETUP: begin
                if (blit_adj_mask[3:2] != 0) blit_adj_mask[3:2] <= 2'b11;
                if (blit_adj_mask[1:0] != 0) blit_adj_mask[1:0] <= 2'b11;
                blitrom_addr_a <= {1'b0, blit_cur_src[12:0]};
                vram_state <= ST_BLIT_WAIT_LO;
            end

            ST_BLIT_WAIT_LO: begin
                vram_state <= ST_BLIT_ROMRD;
            end

            ST_BLIT_ROMRD: begin
                blit_rom_data_lo <= blitrom_qa;
                blitrom_addr_a <= {1'b1, blit_cur_src[12:0]};
                vram_addr_a <= (blit_cur_dst[13:0] + {6'd0, blit_x_cnt}) & 14'h3FFF;
                vram_state <= ST_BLIT_WAIT_HI;
            end

            ST_BLIT_WAIT_HI: begin
                vram_state <= ST_BLIT_RMW_RD;
            end

            ST_BLIT_RMW_RD: begin
                blit_rom_data_hi <= blitrom_qa;
                rmw_old_word     <= {vram_hi_qa, vram_lo_qa};
                vram_state <= ST_BLIT_RMW_WR_LO;
            end

            ST_BLIT_RMW_RD2: begin
                rmw_old_word <= {vram_hi_qa, vram_lo_qa};
                vram_state <= ST_BLIT_RMW_WR_LO;
            end

            ST_BLIT_RMW_WR_LO: begin
                rmw_expdata   = 32'h00000000;
                rmw_layermask = build_layermask(blit_adj_mask[3:0]);
                rmw_expdata   = expand_data(blit_rom_data_lo);
                rmw_layermask = build_layermask(blit_adj_mask[3:0] & 4'b0101);
                rmw_new_word  = (rmw_old_word & ~rmw_layermask) | (rmw_expdata & rmw_layermask);
                rmw_expdata   = expand_data(blit_rom_data_hi);
                rmw_layermask = build_layermask(blit_adj_mask[3:0] & 4'b1010);
                rmw_new_word  = (rmw_new_word & ~rmw_layermask) | (rmw_expdata & rmw_layermask);
                vram_addr_a <= (blit_cur_dst[13:0] + {6'd0, blit_x_cnt}) & 14'h3FFF;
                vram_lo_da  <= rmw_new_word[15:0];
                vram_hi_da  <= rmw_new_word[31:16];
                vram_we_a   <= 1;
                vram_state  <= ST_BLIT_NEXT;
            end

            ST_BLIT_NEXT: begin
                blit_cur_src <= blit_cur_src + 16'd1;
                if (blit_x_cnt == blit_width) begin
                    blit_x_cnt <= 0;
                    if (blit_y_cnt == blit_height) begin
                        vram_state <= ST_IDLE;
                    end
                    else begin
                        blit_y_cnt  <= blit_y_cnt + 8'd1;
                        blit_cur_dst <= blit_cur_dst + 16'd256;
                        blitrom_addr_a <= {1'b0, (blit_cur_src + 16'd1) & 16'h1FFF};
                        vram_state <= ST_BLIT_ROWSTART;
                    end
                end
                else begin
                    blit_x_cnt <= blit_x_cnt + 8'd1;
                    blitrom_addr_a <= {1'b0, (blit_cur_src + 16'd1) & 16'h1FFF};
                    vram_state <= ST_BLIT_WAIT_LO;
                end
            end

            ST_BLIT_ROWSTART: begin
                vram_state <= ST_BLIT_ROMRD;
            end

            default: vram_state <= ST_IDLE;
        endcase
    end
end

wire [7:0] scrolly = video_control[6];
wire [7:0] scrollx = video_control[7];
wire [2:0] maska = (video_control[10] & 8'h28) >> 3;
wire [2:0] maskb =  video_control[10][2:0];
wire [7:0] xora = (video_control[9][5] ^ crt_flip) ? 8'hFF : 8'h00;
wire [7:0] xorb = (video_control[9][4] ^ crt_flip) ? 8'hFF : 8'h00;
wire       enaa = video_control[9][3];
wire       enab = video_control[9][2];
wire       pria = ~video_control[9][1];
wire       prib = ~video_control[9][0];

wire [8:0] scan_x = h_cnt[9:1];
wire [7:0] scan_y = v_cnt[7:0];

wire [7:0] effxa = scrollx + (scan_x[7:0] ^ xora);
wire [7:0] effya = scrolly + (scan_y ^ xora);
wire [7:0] effxb = scan_x[7:0] ^ xorb;
wire [7:0] effyb = scan_y ^ xorb;

reg [31:0] scan_word_a, scan_word_b;
reg [1:0]  scan_effxa_slice, scan_effxb_slice;

wire [13:0] scan_addr_a_w = {effxa[7:2], effya};
wire [13:0] scan_addr_b_w = {effxb[7:2], effyb};

assign vram_addr_b  = scan_addr_a_w;
assign vram_addr_b2 = scan_addr_b_w;

reg [1:0] effxa_slice_hold, effxb_slice_hold;

always_ff @(posedge clk_10m) begin
    effxa_slice_hold <= effxa[1:0];
    effxb_slice_hold <= effxb[1:0];
    scan_word_a      <= {vram_hi_qb,  vram_lo_qb};
    scan_word_b      <= {vram2_hi_qb, vram2_lo_qb};
    scan_effxa_slice <= effxa_slice_hold;
    scan_effxb_slice <= effxb_slice_hold;
end

wire [7:0] vram_slice_a = (scan_effxa_slice == 2'd0) ? scan_word_a[7:0] :
                          (scan_effxa_slice == 2'd1) ? scan_word_a[15:8] :
                          (scan_effxa_slice == 2'd2) ? scan_word_a[23:16] :
                                                       scan_word_a[31:24];

wire [7:0] vram_slice_b = (scan_effxb_slice == 2'd0) ? scan_word_b[7:0] :
                          (scan_effxb_slice == 2'd1) ? scan_word_b[15:8] :
                          (scan_effxb_slice == 2'd2) ? scan_word_b[23:16] :
                                                       scan_word_b[31:24];

wire [3:0] pixa_raw = vram_slice_a[3:0];
wire [3:0] pixb_raw = vram_slice_b[7:4];

wire is_odd_pixel = h_cnt[0];

wire [3:0] pixa_masked = (is_odd_pixel && !(pixa_raw[3])) ? (pixa_raw & {1'b0, maska}) : pixa_raw;
wire [3:0] pixb_masked = (is_odd_pixel && !(pixb_raw[3])) ? (pixb_raw & {1'b0, maskb}) : pixb_raw;

wire [3:0] pixa_final = is_odd_pixel ? pixa_masked : pixa_raw;
wire [3:0] pixb_final = is_odd_pixel ? pixb_masked : pixb_raw;

reg [2:0] final_color;
always_comb begin
    final_color = 3'd0;
    if (enaa && (pria || pixb_raw == 0))
        final_color = final_color | pixa_final[2:0];
    if (enab && (prib || pixa_final == 0))
        final_color = final_color | pixb_final[2:0];
end

wire active_video = ~video_hblank & ~video_vblank;
assign video_r = active_video ? {final_color[2], final_color[2], final_color[2]} : 3'd0;
assign video_g = active_video ? {final_color[1], final_color[1], final_color[1]} : 3'd0;
assign video_b = active_video ? {final_color[0], final_color[0]} : 2'd0;

assign z80_0_i.reset_n = reset; assign z80_0_i.ce = cen_2m5 & ~pause; assign z80_0_i.int_n = n_irq; assign z80_0_i.nmi_n = n_nmi;
assign z80_0_i.di = cpu_Din;
assign mb88_0_i.ena = mcu_ena; assign mb88_0_i.reset_n = mcu_reset_n; assign mb88_0_i.k = mcu_k;
assign mb88_0_i.r_in = {r3_out, r2_out, r1_out, r0_out};
assign mb88_0_i.irq_n = 1'b1; assign mb88_0_i.tc_n = 1'b1; assign mb88_0_i.si_n = 1'b1; assign mb88_0_i.rom_d = mcu_rom_q;

endmodule
