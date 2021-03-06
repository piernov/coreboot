/*
 * Optimized assembly for low-level CPU operations on ARMv7 processors.
 *
 * Cache flushing code based off sys/arch/arm/arm/cpufunc_asm_armv7.S in NetBSD
 *
 * Copyright (c) 2010 Per Odlund <per.odlund@armagedon.se>
 * Copyright (c) 2014 Google Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <arch/asm.h>

/*
 * Dcache invalidations by set/way work by passing a [way:sbz:set:sbz:level:0]
 * bitfield in a register to the appropriate MCR instruction. This algorithm
 * works by initializing a bitfield with the highest-numbered set and way, and
 * generating a "set decrement" and a "way decrement". The former just contains
 * the LSB of the set field, but the latter contains the LSB of the way field
 * minus the highest valid set field... such that when you subtract it from a
 * [way:0:level] field you end up with a [way - 1:highest_set:level] field
 * through the magic of double subtraction. It's quite ingenius, really.
 * Takes care to only use r0-r3 and ip so it's pefectly ABI-compatible without
 * needing to write to memory.
 */

.macro	dcache_apply_all crm
	dsb
	mov	r3, #-2			@ initialize level so that we start at 0

1:	@next_level
	add	r3, r3, #2		@ increment level

	mrc	p15, 1, r0, c0, c0, 1	@ read CLIDR
	and	ip, r0, #0x07000000	@ narrow to LoC
	lsr	ip, ip, #23		@ left align LoC (low 4 bits)
	cmp	r3, ip			@ compare
	bge	3f @done		@ else fall through (r0 == CLIDR)

	add	r2, r3, r3, lsr #1	@ r2 = (level << 1) * 3 / 2
	mov	r1, r0, lsr r2		@ r1 = cache type
	and	r1, r1, #7
	cmp	r1, #2			@ is it data or i&d?
	blt	1b @next_level		@ nope, skip level

	mcr	p15, 2, r3, c0, c0, 0	@ select cache level
	isb
	mrc	p15, 1, r0, c0, c0, 0	@ read CCSIDR

	ubfx	ip, r0, #0, #3		@ get linesize from CCSIDR
	add	ip, ip, #4		@ apply bias
	ubfx	r2, r0, #13, #15	@ get numsets - 1 from CCSIDR
	lsl	r2, r2, ip		@ shift to set position
	orr	r3, r3, r2		@ merge set into way/set/level
	mov	r1, #1
	lsl	r1, r1, ip		@ r1 = set decr

	ubfx	ip, r0, #3, #10		@ get numways - 1 from [to be discarded] CCSIDR
	clz	r2, ip			@ number of bits to MSB of way
	lsl	ip, ip, r2		@ shift by that into way position
	mov	r0, #1
	lsl	r2, r0, r2		@ r2 now contains the way decr
	mov	r0, r3 			@ get sets/level (no way yet)
	orr	r3, r3, ip		@ merge way into way/set/level
	bfc	r0, #0, #4		@ clear low 4 bits (level) to get numset - 1
	sub	r2, r2, r0		@ subtract from way decr

	/* r3 = ways/sets/level, r2 = way decr, r1 = set decr, r0 and ip are free */
2:	mcr	p15, 0, r3, c7, \crm, 2	@ writeback and/or invalidate line
	cmp	r3, #15			@ are we done with this level (way/set == 0)
	bls	1b @next_level		@ yes, go to next level
	lsr	r0, r3, #4		@ clear level bits leaving only way/set bits
	lsls	r0, r0, #14		@ clear way bits leaving only set bits
	subne	r3, r3, r1		@ non-zero?, decrement set #
	subeq	r3, r3, r2		@ zero?, decrement way # and restore set count
	b	2b

3:	@done
	mov	r0, #0			@ default back to cache level 0
	mcr	p15, 2, r0, c0, c0, 0	@ select cache level
	dsb
	isb
	bx	lr
.endm

ENTRY(dcache_invalidate_all)
	dcache_apply_all crm=c6
ENDPROC(dcache_invalidate_all)

ENTRY(dcache_clean_all)
	dcache_apply_all crm=c10
ENDPROC(dcache_clean_all)

ENTRY(dcache_clean_invalidate_all)
	dcache_apply_all crm=c14
ENDPROC(dcache_clean_invalidate_all)
