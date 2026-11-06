***************************************************************
** main_echo.s : 簡易 OS + Step 9 エコーバックプログラム（班の最終成果物）
**   アセンブル: m68k-as -t 400 main_echo.s
**   提出用 1 ファイル化: sh tools/bundle.sh main_echo.s simple_os.s  (→ simple_os.s)
**
**   .include の順番に注意:
**     os_defs.s (定数) → os_init.s (boot を 0x400 番地に置く) → その他
***************************************************************

| ======== ユーザプログラム層（stop_watch.s）の取り込み ========
.include "stop_watch.s"

| ======== begin os_defs.s ========
***************************************************************
** os_defs.s : 定数定義（レジスタのアドレス・システムコール番号など）
**   コードは含まない．すべてのエントリファイルの最初に .include する．
**   出典: テキスト 3.5 節 (p.29), 3.13 節 (p.46), 付録 A.4.3 (p.57-58)
***************************************************************

***************
** レジスタ群の先頭
***************
	.equ REGBASE,   0xFFF000          | DMAP を使用．
	.equ IOBASE,    0x00d00000

***************
** 割り込み関係のレジスタ (付録 B.3.1)
***************
	.equ IVR,       REGBASE+0x300     | 割り込みベクタレジスタ
	.equ IMR,       REGBASE+0x304     | 割り込みマスクレジスタ
	.equ ISR,       REGBASE+0x30c     | 割り込みステータスレジスタ
	.equ IPR,       REGBASE+0x310     | 割り込みペンディングレジスタ

***************
** タイマ関係のレジスタ (付録 B.3.2)
***************
	.equ TCTL1,     REGBASE+0x600     | タイマ１コントロールレジスタ
	.equ TPRER1,    REGBASE+0x602     | タイマ１プリスケーラレジスタ
	.equ TCMP1,     REGBASE+0x604     | タイマ１コンペアレジスタ
	.equ TCN1,      REGBASE+0x608     | タイマ１カウンタレジスタ
	.equ TSTAT1,    REGBASE+0x60a     | タイマ１ステータスレジスタ

***************
** UART1（送受信）関係のレジスタ (付録 B.3.3)
***************
	.equ USTCNT1,   REGBASE+0x900     | UART1 ステータス/コントロールレジスタ
	.equ UBAUD1,    REGBASE+0x902     | UART1 ボーコントロールレジスタ
	.equ URX1,      REGBASE+0x904     | UART1 受信レジスタ
	.equ UTX1,      REGBASE+0x906     | UART1 送信レジスタ

***************
** LED・スイッチ (付録 A.4.3)
***************
	.equ LED7,      IOBASE+0x000002f  | ボード搭載の LED 用レジスタ
	.equ LED6,      IOBASE+0x000002d  | 左から LED7 〜 LED0
	.equ LED5,      IOBASE+0x000002b
	.equ LED4,      IOBASE+0x0000029
	.equ LED3,      IOBASE+0x000003f
	.equ LED2,      IOBASE+0x000003d
	.equ LED1,      IOBASE+0x000003b
	.equ LED0,      IOBASE+0x0000039
	.equ PUSHSW,    0xFFF419          | 押しボタンスイッチ（下位 4bit，押すと 0）
	.equ TOGGLESW,  0xD00041          | トグルスイッチ 8 個

***************
** システムコール番号 (3.12.1 節 p.44)
***************
	.equ SYSCALL_NUM_GETSTRING,   1
	.equ SYSCALL_NUM_PUTSTRING,   2
	.equ SYSCALL_NUM_RESET_TIMER, 3
	.equ SYSCALL_NUM_SET_TIMER,   4

***************
** キュー番号 (3.4.1 節 p.24: 受信 = 0 番，送信 = 1 番)
***************
	.equ QNO_RECV,  0
	.equ QNO_SEND,  1

***************
** キューの制御変数のオフセット (表 3.2, os_queue.s の Q0_INFO / Q1_INFO からの位置)
***************
	.equ TOP,     0
	.equ BOTTOM,  4
	.equ OUT,     8
	.equ IN,      12
	.equ S,       16
| ======== end os_defs.s ========
| ======== begin os_init.s ========
***************************************************************
** os_init.s : 初期化ルーチン (Step 1〜)
**   担当: 初期化（神井，副田）
**   レビュー: タイマ担当（松岡）
**
**   エントリファイルでは os_defs.s の直後に .include すること．
**   boot が .text の先頭 = 0x400 番地に置かれる必要がある (付録 A.1.1.3)．
**   以下の boot はテキスト 3.5 節 (p.29-30) のコードそのまま．
**   Step が進むごとに TODO を埋めていく．
***************************************************************

***************************************************************
** スタック領域の確保
***************************************************************
.section .bss
.even
SYS_STK:
	.ds.b	0x4000          | システムスタック領域
	.even
SYS_STK_TOP:                | システムスタック領域の最後尾

***************************************************************
** 初期化
** 内部デバイスレジスタには特定の値が設定されている．
** その理由を知るには，付録 B にある各レジスタの仕様を参照すること．
***************************************************************
.section .text
.even
boot:
	* スーパーバイザ & 各種設定を行っている最中の割込禁止
	move.w	#0x2700,%SR
	lea.l	SYS_STK_TOP,%SP         | Set SSP

	****************
	** 割り込みベクタの設定
	** 表 B.4 (p.72) を見て，使う例外のベクタに処理ルーチンの
	** 先頭アドレスを書き込む (B.2.4 の move.l #..., 0x110)．
	** TODO: 使わないベクタにも NONE を入れておくと安全 (A.7.6)．
	****************
	move.l	#UART1_INTERRUPT, 0x110 	| レベル 4 (UART1), (64+4)*4
	move.l	#SYSCALL_IF, 0x080			| TRAP #0, (32+0)*4
	move.l	#TIMER1_INTERRUPT, 0x118	| レベル 6 (タイマ1), (64+6)*4

	****************
	** 割り込みコントローラの初期化
	****************
	move.b	#0x40, IVR              | ユーザ割り込みベクタ番号を
	                                | 0x40+level に設定．
	move.l	#0x00ffffff,IMR         | 全割り込みマスク

	****************
	** 送受信 (UART1) 関係の初期化 (割り込みレベルは 4 に固定されている)
	****************
	move.w	#0x0000, USTCNT1        | リセット
	move.w	#0xe100, USTCNT1        | 送受信可能, パリティなし, 1 stop, 8 bit,
	                                | 送受割り込み禁止
	move.w	#0x0038, UBAUD1         | baud rate =  230400 bps

	****************
	** タイマ関係の初期化 (割り込みレベルは 6 に固定されている)
	****************
	move.w	#0x0004, TCTL1          | restart, 割り込み不可,
	                                | システムクロックの 1/16 を単位として計時，
	                                | タイマ使用停止

	****************
	** キューの初期化
	** (Step 0 完成後): os_queue.s の QUEUE_INIT を呼ぶ．
	****************
	jsr	QUEUE_INIT

	****************
	** 割り込みの許可
	** (Step 2〜): IMR で使う割り込みを許可し，走行レベルを下げる
	**       (3.6 節 p.31 の 4 つの準備，B.3.4 の推奨値)．
	****************
	move.w	#0xe108, USTCNT1
	move.l	#0xff3ff9, IMR
	move.w	#0x2000, %SR

	bra	MAIN                    | ユーザプログラム / テストプログラムへ

/**test**/
| ======== end os_init.s ========
| ======== begin user_echo.s ========
***************************************************************
** user_echo.s : Step 9 のユーザプログラム（エコーバック + タイマ）
**   テキスト 3.13.1 節 (p.46-47) のコードそのまま．
**   システムコールの番号は os_defs.s で定義済み．
**   確認すること (3.13.2 節): キー入力がエコーバックされる．
**   5 秒ごとに ****** が表示され改行，5 回で終了．
***************************************************************

****************************************************************
*** プログラム領域
****************************************************************
.section .text
.even
MAIN:
	** 走行モードとレベルの設定 (「ユーザモード」への移行処理)
	move.w	#0x0000, %SR            | USER MODE, LEVEL 0
	lea.l	USR_STK_TOP,%SP         | user stack の設定

	** システムコールによる RESET_TIMER の起動
	move.l	#SYSCALL_NUM_RESET_TIMER,%D0
	trap	#0

	** システムコールによる SET_TIMER の起動
	move.l	#SYSCALL_NUM_SET_TIMER, %D0
	move.w	#50000, %D1
	move.l	#TT,    %D2
	trap	#0

******************************
* sys_GETSTRING, sys_PUTSTRING のテスト
* ターミナルの入力をエコーバックする
******************************
LOOP:
	move.l	#SYSCALL_NUM_GETSTRING, %D0
	move.l	#0,   %D1               | ch   = 0
	move.l	#BUF, %D2               | p    = #BUF
	move.l	#256, %D3               | size = 256
	trap	#0

	move.l	%D0, %D3                | size = %D0 (length of given string)
	move.l	#SYSCALL_NUM_PUTSTRING, %D0
	move.l	#0, %D1                 | ch = 0
	move.l	#BUF,%D2                | p  = #BUF
	trap	#0
	bra	LOOP

******************************
* タイマのテスト
* '******' を表示し改行する．
* ５回実行すると，RESET_TIMER をする．
******************************
TT:
	movem.l	%D0-%D7/%A0-%A6,-(%SP)
	cmpi.w	#5,TTC                  | TTC カウンタで 5 回実行したかどうか数える
	beq	TTKILL                  | 5 回実行したら，タイマを止める

	move.l	#SYSCALL_NUM_PUTSTRING,%D0
	move.l	#0,    %D1              | ch = 0
	move.l	#TMSG, %D2              | p  = #TMSG
	move.l	#8,    %D3              | size = 8
	trap	#0

	addi.w	#1,TTC                  | TTC カウンタを 1 つ増やして
	bra	TTEND                   | そのまま戻る
TTKILL:
	move.l	#SYSCALL_NUM_RESET_TIMER,%D0
	trap	#0
TTEND:
	movem.l	(%SP)+,%D0-%D7/%A0-%A6
	rts

****************************************************************
*** 初期値のあるデータ領域
****************************************************************
.section .data
TMSG:
	.ascii	"******\r\n"             | \r: 行頭へ (キャリッジリターン)
	.even                           | \n: 次の行へ (ラインフィード)
TTC:
	.dc.w	0
	.even

****************************************************************
*** 初期値の無いデータ領域
****************************************************************
.section .bss
BUF:
	.ds.b	256                     | BUF[256]
	.even
USR_STK:
	.ds.b	0x4000                  | ユーザスタック領域
	.even
USR_STK_TOP:                            | ユーザスタック領域の最後尾
| ======== end user_echo.s ========
| ======== begin os_interface.s ========
***************************************************************
** os_interface.s : 割り込みインタフェース・システムコールインタフェース
**   担当: 初期化（神井，副田）
**   レビュー: タイマ担当（松岡）
**
**   ここに置くルーチンは割り込み (例外) で起動されるので，rts ではなく rte で戻る．
**   各ルーチンの先頭アドレスは os_init.s でベクタに登録する (表 B.4 p.72)．
***************************************************************

.section .text
.even

***************************************************************
** UART1_INTERRUPT : 送受信割り込み用のハードウェア割り込みインタフェース
**   (Step 4: 3.8.2 節 p.34 の (1)(2),  Step 6: 3.10.3 節 p.39 の (3)〜(6))
**   レベル 4 (UART1) のベクタに登録する．
**   【注意】UTX1 / URX1 は一度読むと更新されるので，別レジスタにコピーして使う．
***************************************************************
UART1_INTERRUPT:

    * D0~D3の元の値を保存 (複数レジスタは movem でまとめて積む)
    movem.l %D0-%D3, -(%SP)

    ******** 送信 (Step 4) ********
    * UTX1の内容を取得
    move.w UTX1, %D0

    * bit15だけを取り出す
    andi.w #0x8000, %D0

    * bit15が0なら送信処理を行わない
    beq NOT_SEND

    * INTERPUTにUART1のチャネル番号0を渡す
    move.l #0x0000, %D1

    * 送信担当のINTERPUTを呼び出す
    jsr INTERPUT

NOT_SEND:

    ******** 受信 (Step 6) ********
    * URX1の内容を取得 (一度読むと更新されるので，以降はD3のコピーを使う)
    move.w URX1, %D3

    * bit13 (DATA READY) を調べる (btst は D3 を壊さない)
    btst #13, %D3

    * bit13が0なら受信処理を行わない
    beq NOT_RECEIVE

    * INTERGETにチャネル番号0と受信データ (URX1の下位8bit) を渡す
    move.l #0x0000, %D1
    move.b %D3, %D2

    * 受信担当のINTERGETを呼び出す
    jsr INTERGET

NOT_RECEIVE:

    * D0~D3を元の値に復元 (退避と同じ組)
    movem.l (%SP)+, %D0-%D3

    * 割り込み前の処理に復帰
    rte
***************************************************************
** TIMER1_INTERRUPT : タイマ用のハードウェア割り込みインタフェース
**   (Step 7: 3.11.2 節 p.42 の (1)〜(3))
**   レベル 6 (タイマ 1) のベクタに登録する．
***************************************************************
TIMER1_INTERRUPT:
	movem.l	%d0-%d7/%a0-%a6,-(%sp)  | (1) レジスタ退避 (CALL_RP 先で何が壊されるか分からないので全部)
	move.w	TSTAT1, %d0             | (2) TSTAT1 をワードで読む (0 クリア前の読み出しも兼ねる)
	btst	#0, %d0                 |     bit0 = コンペアイベント発生
	beq		TIMER1_EXIT             |     0 ならタイマ割り込みではないので何もしない
	move.w	#0, TSTAT1              |     TSTAT1 を 0 クリア
	jsr	CALL_RP                 	|     task_p の指すルーチンを呼ぶ
TIMER1_EXIT:
	movem.l	(%sp)+,%d0-%d7/%a0-%a6  | (3) レジスタ復帰
	rte

***************************************************************
** SYSCALL_IF : システムコールインタフェース (Step 8: 3.12.2 節 p.44-45)
**   TRAP #0 のベクタに登録する．
**   【入力】  %D0.L = システムコール番号 (os_defs.s の SYSCALL_NUM_*)
**             %D1〜  = 各システムコールの引数
**   【戻り値】%D0.L = システムコールの結果
**   【注意】%D0 を退避・復帰すると戻り値が消える (p.45)．
**           番号 → ルーチンへの変換は拡張しやすい形を工夫する．
***************************************************************
SYSCALL_IF:
	movem.l	%a0,-(%sp)              | 作業用の %A0 だけ退避 (%D0 は戻り値，%D1〜 は引数なので触らない)
	cmpi.l	#1, %d0                 | 番号 < 1 なら範囲外として終了
	bcs		SYSCALL_IF_EXIT         |     (符号なし比較なので負の値も弾ける)
	cmp.l	#SYSCALL_NUM_SET_TIMER, %d0 | 番号 > 最大の番号なら範囲外として終了
	bhi		SYSCALL_IF_EXIT
	lea.l	SYSCALL_TABLE, %a0      | %A0 = テーブルの先頭
	lsl.l 	#2, %d0                 | 番号 × 4 = テーブル内のオフセット (1 要素 4 バイト)
	movea.l	(%a0, %d0.l), %a0       | %A0 = 呼び出すルーチンの先頭アドレス
	jsr		(%a0)                   | 各ルーチンへ (戻り値は %D0 に入る)
SYSCALL_IF_EXIT:
	movem.l	(%sp)+,%a0              | %A0 を復帰 (%D0 は復帰しない)
	rte

***************************************************************
** SYSCALL_TABLE : システムコール番号 → ルーチンの先頭アドレスの対応表
**   番号 n のルーチンは先頭から n*4 バイト目．
**   システムコールを増やすときは末尾に 1 行足し，SYSCALL_IF の上限も変える．
***************************************************************
SYSCALL_TABLE:
	.dc.l	0				| 0: 未使用
	.dc.l	GETSTRING		| 1: SYSCALL_NUM_GETSTRING
	.dc.l	PUTSTRING		| 2: SYSCALL_NUM_PUTSTRING 
	.dc.l	RESET_TIMER		| 3: SYSCALL_NUM_RESET_TIMER 
	.dc.l	SET_TIMER		| 4: SYSCALL_NUM_SET_TIMER


***************************************************************
** NONE : 何もしない例外処理 (付録 A.7.6)
**   使わない例外ベクタに登録しておくと，予期しない割り込みで暴走しにくい．
***************************************************************
NONE:
	rte
| ======== end os_interface.s ========
| ======== begin os_queue.s ========
***************************************************************
** os_queue.s : キュー (Step 0, テキスト 3.4 節 p.24-28)
**   担当: 受信（安森）・送信（田邉）
**   レビュー: 受信担当（安森）⇔ 送信担当（田邉）
**
**   キューは 2 本: 0 番 = 受信 (QNO_RECV)，1 番 = 送信 (QNO_SEND)．各 256 バイト．
**   制御用の変数 (表 3.2): top, bottom, out, in, s
**   スーパーバイザモードで実行される (ユーザモードから直接呼ばないこと)．
***************************************************************

.section .text
.even

.equ	TOP,	0
.equ	BOTTOM,	4
.equ	OUT,	8
.equ	IN,	12
.equ	S,	16

***************************************************************
** QUEUE_INIT : 2 本のキューを初期化する (3.4.1 節)
**   【入力】なし   【戻り値】なし
	**   TODO: top/out/in ← データ領域の先頭，bottom ← 末尾，s ← 
***************************************************************
QUEUE_INIT:
	movem.l %a2-%a3, -(%sp)     | 使用するレジスタの退避

    * キュー0 (受信用) の初期化
    lea.l   BF0_START, %a2
    lea.l   BF0_END, %a3
    move.l  %a2, top0
    move.l  %a3, bottom0        | bottom には末尾アドレスを入れる
    move.l  %a2, out0
    move.l  %a2, in0
    move.l  #0, s0

    * キュー1 (送信用) の初期化
    lea.l   BF1_START, %a2
    lea.l   BF1_END, %a3
    move.l  %a2, top1
    move.l  %a3, bottom1
    move.l  %a2, out1
    move.l  %a2, in1
    move.l  #0, s1

	movem.l (%sp)+, %a2-%a3     | レジスタの復帰
	rts

***************************************************************
** INQ(no, data) : 番号 no のキューにデータを 1 つ入れる (3.4.2 節)
**   【入力】  %D0.L = キュー番号 no,  %D1.B = 書き込む 8bit データ
**   【戻り値】%D0.L = 0 (失敗: queue full) / 1 (成功)
**   【処理内容】p.25 の (1)〜(7)．走行レベルの退避・割り込み禁止を忘れずに．
***************************************************************
INQ:
	move.w  %sr, -(%sp)        /*(1)走行レベル(%SR)をa3に退避*/
	movem.l %a0-%a1,-(%sp)
	move.w  #0x2700, %sr    /*(2)割り込み禁止 */
	lea.l Q0_INFO,%a0
	cmpi.l #0,%d0
	beq INQ_CHECK_FULL
	lea.l Q1_INFO,%a0
INQ_CHECK_FULL:	 /*(3) s== 256 でqueue full*/
	cmpi.l  #256, S(%a0)
	beq     INQ_FULL
	movea.l IN(%a0),%a1 /*(4)m[in] = data*/
	move.b %d1, (%a1)
	cmpa.l BOTTOM(%a0), %a1 /*(5)*/
	beq INQ_WRAP
	adda.l #1,%a1
	bra INQ_UPDATE

INQ_WRAP:
	movea.l TOP(%a0), %a1

INQ_UPDATE:	
	move.l %a1,IN(%a0)  /*更新したin保存*/

	addi.l #1, S(%a0)  /*(6)*/
	moveq.l #1,%d0
	bra INQ_BACK

INQ_FULL:
	moveq #0,%d0

INQ_BACK:
	movem.l (%sp)+, %a0-%a1
	move.w (%sp)+,%sr
	rts

***************************************************************
** OUTQ(no, data) : 番号 no のキューからデータを 1 つ取り出す (3.4.2 節)
**   【入力】  %D0.L = キュー番号 no
**   【戻り値】%D0.L = 0 (失敗: queue empty) / 1 (成功)
**             %D1.B = 取り出した 8bit データ
**   【処理内容】p.26 の (1)〜(7)．
***************************************************************
OUTQ:
	move.w %SR, -(%SP)
	movem.l %a0-%a1,-(%sp)
	ori.w #0x2700, %SR

	cmpi.l #0, %d0
	beq	OUTQ_Q0

*キュー1
OUTQ_Q1:
	cmpi.l #0, s1
	beq	OUTQ_EMPTY_OUT1
	
	move.l	out1, %a0
	move.b	(%a0), %d1

	cmp.l	bottom1, %a0
	bne	OUTQ_PLS_OUT1
	move.l	top1, %a0
	bra	OUTQ_UPDATTE_OUT1
OUTQ_PLS_OUT1:
	addq.l	#1, %a0
OUTQ_UPDATTE_OUT1:
	move.l %a0, out1

	subq.l #1, s1
	move.l #1, %d0
	
	bra OUTQ_EXIT
OUTQ_EMPTY_OUT1:
	move.l #0, %d0
	bra OUTQ_EXIT

*キュー0
OUTQ_Q0:
	cmpi.l #0, s0
	beq	OUTQ_EMPTY_OUT0
	
	move.l	out0, %a0
	move.b	(%a0), %d1

	cmp.l	bottom0, %a0
	bne	OUTQ_PLS_OUT0
	move.l	top0, %a0
	bra	OUTQ_UPDATTE_OUT0
OUTQ_PLS_OUT0:
	addq.l	#1, %a0
OUTQ_UPDATTE_OUT0:
	move.l %a0, out0

	subq.l #1, s0
	move.l #1, %d0
	
	bra OUTQ_EXIT
OUTQ_EMPTY_OUT0:
	move.l #0, %d0
	bra OUTQ_EXIT

OUTQ_EXIT:
	movem.l (%sp)+, %a0-%a1
	move.w (%SP)+, %SR
	rts
***************************************************************
** キューの領域 (.bss に .ds で確保する: 3.4.1 節)
***************************************************************
.section .bss
.even

	/*TODO: データ領域 256 バイト × 2 と，変数 top/bottom/out/in/s*/
* キュー0 (受信用: 256バイト)
BF0_START:  .ds.b 255
BF0_END:    .ds.b 1

* キュー1 (送信用: 256バイト)
BF1_START:  .ds.b 255
BF1_END:    .ds.b 1

.even
* キュー0 の制御変数 (先頭から +0, +4, +8, +12, +16 バイト)
Q0_INFO:
top0:       .ds.l 1
bottom0:    .ds.l 1
out0:       .ds.l 1
in0:        .ds.l 1
s0:         .ds.l 1

* キュー1 の制御変数 (Q0_INFO の直後 = +20バイト目から配置)
Q1_INFO:
top1:       .ds.l 1
bottom1:    .ds.l 1
out1:       .ds.l 1
in1:        .ds.l 1
s1:         .ds.l 1
| ======== end os_queue.s ========
| ======== begin os_uart.s ========
***************************************************************
** os_uart.s : 送受信制御部 (Step 4〜6)
**   担当: 送信 = INTERPUT, PUTSTRING（田邉）
**         受信 = INTERGET, GETSTRING（安森）
**   レビュー: 受信担当（安森）⇔ 送信担当（田邉）
**
**   チャネル引数 ch は本実験では常に 0 (UART1)．付録 C の 2 チャンネル化に
**   備えて，テキストどおり ch を受け取る形で書く (3.8.1 節の注)．
**   レジスタの保存と復元は付録 B.2.3 を参照．
***************************************************************

.section .text
.even



***************************************************************
** INTERPUT(ch) : 送信割り込み処理 (Step 4, 3.8.1 節 p.33)
**   【入力】  %D1.L = チャネル ch
**   【戻り値】なし
**   【処理内容】p.33 の (1)〜(5)．キューが空なら送信割り込みをマスク．
**              UTX1 への書き込みでは上位 8bit のヘッダを忘れずに．
***************************************************************
INTERPUT:
	move.w %SR, -(%SP)
	move.w #0x2700, %sr /* 割り込み禁止に */

	movem.l %d0-%d1, -(%sp)
	
    cmpi.l #0, %d1
	bne	INTERPUT_BACK

    move.l #1, %d0
    jsr OUTQ /* 成功不成功はd0へ */
    
    cmpi.l #0, %d0
    beq INTERPUT_MASK

    andi.l #0x000000FF, %d1 /* 下位8bit以外クリア */
    ori.w #0x0800, %d1 /* 上位8ビット制御ビット　フロー制御は行わない */
    move.w %d1, UTX1
    bra INTERPUT_BACK


INTERPUT_MASK:
    andi.w #0xfffb, USTCNT1 /* 最下位ビットのみ0にし他は影響しない */
    bra INTERPUT_BACK
    
INTERPUT_BACK:
	movem.l (%sp)+, %d0-%d1
    move.w (%SP)+, %SR

rts

***************************************************************
** PUTSTRING(ch, p, size) : 送信キューにデータを入れる (Step 5, 3.9.1 節 p.35)
**   【入力】  %D1.L = ch,  %D2.L = 先頭アドレス p,  %D3.L = データ数 size
**   【戻り値】%D0.L = 実際にキューに入れたデータ数 sz
**   【処理内容】p.35 の (1)〜(10)．最後に送信割り込みを許可 (USTCNT1)．
***************************************************************
PUTSTRING:
	move.w %SR, -(%SP)
    movem.l %d1-%d5/%a0-%a1, -(%sp)

    cmpi.l #0, %d1
    bne PUTSTRING_END

    move.l #0, %d4 /* szをd4 */
    movea.l %d2, %a0 /* iをa0 */
    move.l %d3, %d5 /* d5にサイズを保持 */

    cmpi.l #0, %d5 /* sizeが0かどうか */
    beq PUTSTRING_FINISH

PUTSTRING_CHECK:    
    cmp.l %d5, %d4 /* szとsize比較 */
    beq PUTSTRING_ENABLE

    move.l #1, %d0 /* キュー番号 */
    move.b (%a0), %d1 /* 格納データ */
    jsr INQ

    cmpi.l #0, %d0
    beq PUTSTRING_ENABLE

    addq.l #1, %d4
    addq.l #1, %a0

    bra PUTSTRING_CHECK

PUTSTRING_ENABLE:
    ori.w #0x0004, USTCNT1 /* USTCNT1のbitを1に */

PUTSTRING_FINISH:
    move.l %d4, %d0
    bra PUTSTRING_BACK

PUTSTRING_END:
    move.l #0, %d0

PUTSTRING_BACK:
    movem.l (%sp)+, %d1-%d5/%a0-%a1
    move.w (%SP)+, %SR 
	rts

***************************************************************
** INTERGET(ch, data) : 受信割り込み処理 (Step 6, 3.10.2 節 p.38-39)
**   【入力】  %D1.L = ch,  %D2.B = 受信データ data
**   【戻り値】なし
**   【処理内容】ch = 0 なら INQ(0, data)．
**   【注意】INQ を呼ぶときは ch=%D0.L, data=%D1.B とレジスタがずれる．
***************************************************************
INTERGET:
    movem.l %d0-%d1, -(%sp)             /*作業用レジスタの退避(1) ch ≠ 0 ならば何もせず終了 (終了処理へジャンプ)*/
    cmpi.l  #0, %d1
    bne     INTERGET_EXIT

   /*(2) INQ(0, data) により，受信キュー(0番)に data を格納する*/
    moveq.l #0, %d0                     /*キュー番号 no = 0 → %D0.L*/
    move.b  %d2, %d1                    /*受信データ data → %D1.B (レジスタのずれ調整)*/
    jsr     INQ                         /*INQ の復帰値は無視してよい*/

INTERGET_EXIT:
    movem.l (%sp)+, %d0-%d1             /*退避したレジスタの復元*/
    rts

***************************************************************
** GETSTRING(ch, p, size) : 受信キューからデータを取り出す (Step 6, 3.10.1 節 p.38)
**   【入力】  %D1.L = ch,  %D2.L = 書き込み先アドレス p,  %D3.L = データ数 size
**   【戻り値】%D0.L = 実際に取り出したデータ数 sz
**   【処理内容】p.38 の (1)〜(9)．
***************************************************************
GETSTRING:
    movem.l %d1-%d4/%a0, -(%sp)         /*作業用レジスタの退避 (%D0は戻り値のため退避しない)*/

    /*(1) ch ≠ 0 ならば何もせず終了 (戻り値 0 で終了)*/
    cmpi.l  #0, %d1
    bne     GETSTRING_ERR

    /*(2) sz ← 0 (%D4.L を sz として使用)，i ← p (%A0 を i として使用)*/
    moveq.l #0, %d4                     /*sz = 0*/
    movea.l %d2, %a0                    /*i = p*/

GETSTRING_LOOP:
    /*(3) sz == size ならば (9) へ*/
    cmp.l   %d3, %d4
    beq     GETSTRING_DONE

    /*(4) OUTQ(0, data) により受信キュー(0番)から 8bit データ data を取り出す*/
    moveq.l #0, %d0                     /*キュー番号 no = 0 → %D0.L*/
    jsr     OUTQ                        /*戻り値: %D0.L = 0 or 1, %D1.B = data*/

    /*(5) OUTQ の復帰値 (%D0) が 0 ならば (9) へ*/
    cmpi.l  #0, %d0
    beq     GETSTRING_DONE

    /*(6) アドレス i で始まる領域に data をコピー ＆ (7) sz++, i++*/
    move.b  %d1, (%a0)+                 /*:m[i] = data, i++*/
    addq.l  #1, %d4                     /*sz++*/

    /*(8) (3) へ戻る*/
    bra     GETSTRING_LOOP

GETSTRING_DONE:
    /* (9) %D0 ← sz として終了*/
    move.l  %d4, %d0
    bra     GETSTRING_EXIT

GETSTRING_ERR:
    moveq.l #0, %d0                     /*ch ≠ 0 の場合は 0 を返す*/

GETSTRING_EXIT:
    movem.l (%sp)+, %d1-%d4/%a0         /*退避したレジスタの復元*/
    rts
| ======== end os_uart.s ========
| ======== begin os_timer.s ========
***************************************************************
** os_timer.s : タイマ制御部 (Step 7, テキスト 3.11.1 節 p.41-42)
**   担当: タイマ（松岡）
**   レビュー: 初期化担当（神井，副田）
***************************************************************

.section .text
.even

***************************************************************
** RESET_TIMER() : タイマ割り込みを不可にし，タイマを停止する
**   【入力】なし   【戻り値】なし
**   【処理内容】TCTL1 を設定 (restart, 割り込み不可, SYSCLK/16, タイマ停止)
***************************************************************
RESET_TIMER:
	move.w #0x004, TCTL1 /*p80より00100(2進数)*/
	rts

***************************************************************
** SET_TIMER(t, p) : t * 0.1 msec ごとに p 番地のルーチンを呼ぶよう設定
**   【入力】  %D1.W = 割り込み周期 t (型に注意),  %D2.L = ルーチンの先頭アドレス p
**   【戻り値】なし
**   【処理内容】p.41 の (1)〜(4)．TPRER1 の値は自分で求める．
***************************************************************
SET_TIMER:
	move.l %D2, task_p /*処理(1)*/
	move.w #206, TPRER1 /*処理(2)*/
	move.w %D1, TCMP1 /*処理(3)*/
	move.w #0x0015, TCTL1 /*p80より10101(2進数)*/
	rts

***************************************************************
** CALL_RP() : タイマ割り込み時に task_p の指すルーチンを呼び出す
**   【入力】なし   【戻り値】なし
**   図 3.5 (p.42) を参照．
***************************************************************
CALL_RP:
	movem.l %A0, -(%SP)
	movea.l task_p, %A0 /*task_pの中身をA0にコピー*/
	jsr (%A0) /*処理(1)*/
	movem.l (%SP)+, %A0
	rts

***************************************************************
** 大域変数 (p.41【注意】: task_p は .bss で定義しておく)
***************************************************************
.section .bss
.even
task_p:
	.ds.l	1               | タイマ割り込みで呼ぶルーチンの先頭アドレス

/*test1*/
| ======== end os_timer.s ========
