#
# Generate uvutil.c
# $Id: uvutil.c.sh,v 1.10 2002-06-25 11:42:34 shirok Exp $
#

#==========================================================
# prologue
#

cat <<EOF
/*
 * uvutil - additional uniform vector utilities
 *
 *  Copyright(C) 2002 by Shiro Kawai (shiro@acm.org)
 *
 *  Permission to use, copy, modify, distribute this software and
 *  accompanying documentation for any purpose is hereby granted,
 *  provided that existing copyright notices are retained in all
 *  copies and that this notice is included verbatim in all
 *  distributions.
 *  This software is provided as is, without express or implied
 *  warranty.  In no circumstances the author(s) shall be liable
 *  for any damages arising out of the use of this software.
 *
 * This file is automatically generated from uvutil.c.scm
 * $Id: uvutil.c.sh,v 1.10 2002-06-25 11:42:34 shirok Exp $
 */

#include <stdlib.h>
#include <math.h>
#include <limits.h>
#include <string.h>  /* for memcpy() */
#include <gauche.h>
#include <gauche/extend.h>
#include "gauche/uvector.h"
#include "gauche/arith.h"
#include "uvectorP.h"

#define SIZECHK(d, a, b)                                        \\
  do {                                                          \\
    if ((a)->size != (b)->size) {                               \\
      Scm_Error("Vector size doesn't match: %S and %S", a, b);  \\
    }                                                           \\
  SCM_ASSERT((a)->size == (d)->size);                           \\
  } while (0)

#define SIZECHKL(lis, len, target)                                         \\
  do {                                                                     \\
    if (Scm_Length(lis) != (len)) {                                        \\
       Scm_Error("List length doesn't match the target vector: %S and %S", \\
                 (target), (lis));                                         \\
    }                                                                      \\
  } while (0)

#define SIZECHKV(vec, len, target)                                         \\
  do {                                                                     \\
    if (SCM_VECTOR_SIZE(vec) != (len)) {                                   \\
       Scm_Error("Vector size doesn't match: %S and %S",                   \\
                 (target), (vec));                                         \\
    }                                                                      \\
  } while (0)

/*
 * Auxiliary procedures
 */

#define CLAMP_LO_RET(val, clamp) \
    do { if (CLAMP_LO_P(clamp)) return (val); else UV_OVERFLOW; } while (0)
#define CLAMP_HI_RET(val, clamp) \
    do { if (CLAMP_HI_P(clamp)) return (val); else UV_OVERFLOW; } while (0)
   

/*
 * Word-wise operations
 */

/* signed word addition */
static long sadd(long x, long y, int clamp)
{
    long r, v;
    SADDOV(r, v, x, y);
    if (v > 0) CLAMP_HI_RET(LONG_MAX, clamp);
    if (v < 0) CLAMP_LO_RET(LONG_MIN, clamp);
    return r;
}

/* unsigned word addition */
static u_long uadd(u_long x, u_long y, int clamp)
{
    u_long r, v;
    UADDOV(r, v, x, y);
    if (v) CLAMP_HI_RET(SCM_ULONG_MAX, clamp);
    return r;
}

/* signed word subtract */
static long ssub(long x, long y, int clamp)
{
    long r, v;
    SSUBOV(r, v, x, y);
    if (v > 0) CLAMP_HI_RET(LONG_MAX, clamp);
    if (v < 0) CLAMP_LO_RET(LONG_MIN, clamp);
    return r;
}

/* unsigned word subtract */
static u_long usub(u_long x, u_long y, int clamp)
{
    u_long r, v;
    USUBOV(r, v, x, y);
    if (v) CLAMP_LO_RET(0, clamp);
    return r;
}

/* u_long multiplication. */
static u_long umul(u_long x, u_long y, int clamp)
{
    u_long r, v;
    UMULOV(r, v, x, y);
    if (v) CLAMP_HI_RET(SCM_ULONG_MAX, clamp);
    return r;
}

/* signed long multiplication */
static long smul(long x, long y, int clamp)
{
    long r, v;
    SMULOV(r, v, x, y);
    if (v > 0) CLAMP_HI_RET(LONG_MAX, clamp);
    if (v < 0) CLAMP_LO_RET(LONG_MIN, clamp);
    return r;
}

/*
 * word vs object operations
 */

/* signed integer addition, non-full word */
static long saddobj_small(long x, ScmObj y, long min, long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        r = sadd(x, SCM_INT_VALUE(y), clamp);
        if (r < min) CLAMP_LO_RET(min, clamp);
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        CLAMP_BIG(r, y, min, max, clamp);
    } else BADOBJ(y);
    return r;
}

/* signed integer addition, full word */
static long saddobj(long x, ScmObj y, ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        return sadd(x, SCM_INT_VALUE(y), clamp);
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r = Scm_Add2(Scm_MakeInteger(x), y);
        if (SCM_INTP(r)) return SCM_INT_VALUE(r);
        if (Scm_NumCmp(r, bigmin) < 0) CLAMP_LO_RET(LONG_MIN, clamp);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(LONG_MAX, clamp);
        return Scm_GetInteger(r);
    }
    BADOBJ(y);
    return 0; /*dummy*/
}

/* unsigned integer addition, non-full word */
static u_long uaddobj_small(u_long x, ScmObj y, u_long min, u_long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        long yv = SCM_INT_VALUE(y);
        if (yv < 0) r = usub(x, -yv, clamp);
        else        r = uadd(x, yv, clamp);
        if (r < min) CLAMP_LO_RET(min, clamp);
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        CLAMP_BIG(r, y, min, max, clamp);
    } else BADOBJ(y);
    return r;
}

/* unsigned integer addition, full word */
static u_long uaddobj(u_long x, ScmObj y,
                      ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        long yv = SCM_INT_VALUE(y);
        if (yv < 0) return usub(x, -yv, clamp);
        else        return uadd(x, yv, clamp);
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r = Scm_Add2(Scm_MakeIntegerFromUI(x), y);
        if (SCM_INTP(r)) {
            if (SCM_INT_VALUE(r) < 0) CLAMP_LO_RET(0, clamp);
            else return SCM_INT_VALUE(r);
        }
        if (Scm_NumCmp(r, bigmin) < 0) CLAMP_LO_RET(0, clamp);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(SCM_ULONG_MAX, clamp);
        return Scm_GetUInteger(r);
    } else BADOBJ(y);
    return 0; /*dummy*/
}

/* signed integer subtract, non-full word */
static long ssubobj_small(long x, ScmObj y, long min, long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        r = ssub(x, SCM_INT_VALUE(y), clamp);
        if (r < min) CLAMP_LO_RET(min, clamp);
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        if (SCM_BIGNUM_SIGN(y) < 0) CLAMP_HI_RET(max, clamp);
        else                        CLAMP_LO_RET(min, clamp);
    } else BADOBJ(y);
    return r;
}

/* signed integer subtract, full word */
static long ssubobj(long x, ScmObj y,
                    ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        return ssub(x, SCM_INT_VALUE(y), clamp);
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r = Scm_Subtract2(Scm_MakeInteger(x), y);
        if (SCM_INTP(r)) return SCM_INT_VALUE(r);
        if (Scm_NumCmp(r, bigmin) < 0) CLAMP_LO_RET(LONG_MIN, clamp);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(LONG_MAX, clamp);
        return Scm_GetInteger(r);
    }
    BADOBJ(y);
    return 0; /* dummy */
}

/* unsigned integer addition, non-full word */
static u_long usubobj_small(u_long x, ScmObj y, u_long min, u_long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        long yv = SCM_INT_VALUE(y);
        if (yv < 0) r = uadd(x, -yv, clamp);
        else        r = usub(x, yv, clamp);
        if (r < min) CLAMP_LO_RET(min, clamp);
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        if (SCM_BIGNUM_SIGN(y) < 0) CLAMP_HI_RET(max, clamp);
        else                        CLAMP_LO_RET(min, clamp);
    } else BADOBJ(y);
    return r;
}

/* unsigned integer subtract, full word */
static u_long usubobj(u_long x, ScmObj y,
                      ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        long yv = SCM_INT_VALUE(y);
        if (yv < 0) return uadd(x, -yv, clamp);
        else        return usub(x, yv, clamp);
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r = Scm_Subtract2(Scm_MakeIntegerFromUI(x), y);
        if (SCM_INTP(r)) {
            if (SCM_INT_VALUE(r) < 0) CLAMP_LO_RET(0, clamp);
            else return SCM_INT_VALUE(r);
        }
        if (Scm_NumCmp(r, bigmin) < 0) CLAMP_LO_RET(0, clamp);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(SCM_ULONG_MAX, clamp);
        return Scm_GetUInteger(r);
    }
    BADOBJ(y);
    return 0; /*dummy*/
}

/* signed integer addition, non-full word */
static long smulobj_small(long x, ScmObj y, long min, long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        r = smul(x, SCM_INT_VALUE(y), clamp);
        if (r < min) CLAMP_LO_RET(min, clamp);
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        if (x != 0) {
            if (x * SCM_BIGNUM_SIGN(y) > 0) CLAMP_HI_RET(max, clamp);
            else                            CLAMP_LO_RET(min, clamp);
        }
    } else BADOBJ(y);
    return r;
}

/* signed integer multiplication, full word */
static long smulobj(long x, ScmObj y,
                    ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        return smul(x, SCM_INT_VALUE(y), clamp);
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r = Scm_Multiply2(Scm_MakeInteger(x), y);
        if (SCM_INTP(r)) return SCM_INT_VALUE(r);
        if (Scm_NumCmp(r, bigmin) < 0) CLAMP_LO_RET(LONG_MIN, clamp);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(LONG_MAX, clamp);
        return Scm_GetInteger(r);
    }
    BADOBJ(y);
    return 0; /*dummy*/
}

/* unsigned integer multiplication, non-full word */
static u_long umulobj_small(u_long x, ScmObj y, u_long min, u_long max, int clamp)
{
    long r = 0;
    if (SCM_INTP(y)) {
        if (SCM_INT_VALUE(y) < 0) CLAMP_LO_RET(0, clamp);
        r = umul(x, SCM_INT_VALUE(y), CLAMP_HI_P(clamp));
        if (r > max) CLAMP_HI_RET(max, clamp);
    } else if (SCM_BIGNUMP(y)) {
        if (x != 0) CLAMP_BIG(r, y, min, max, clamp);
    } else BADOBJ(y);
    return r;
}

/* unsigned integer multiplication, full word */
static u_long umulobj(u_long x, ScmObj y, 
                      ScmObj bigmin, ScmObj bigmax, int clamp)
{
    if (SCM_INTP(y)) {
        if (SCM_INT_VALUE(y) < 0) CLAMP_LO_RET(0, clamp);
        return umul(x, SCM_INT_VALUE(y), CLAMP_HI_P(clamp));
    } else if (SCM_BIGNUMP(y)) {
        ScmObj r;
        if (SCM_BIGNUM_SIGN(y) < 0) CLAMP_LO_RET(0, clamp);
        if (SCM_BIGNUM_SIGN(y) == 0) return 0;
        r = Scm_Multiply2(Scm_MakeIntegerFromUI(x), y);
        if (Scm_NumCmp(r, bigmax) > 0) CLAMP_HI_RET(SCM_ULONG_MAX, clamp);
        return Scm_GetUInteger(r);
    }
    BADOBJ(y);
    return 0; /*dummy*/
}

EOF

#=================================================================
# Template for binary operation
#

binop() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"

    cat <<EOF
ScmObj Scm_${vecttype}Op(Scm${vecttype} *dst, Scm${vecttype} *v0,
                         ScmObj operand, int op, int clamp)
{
    int i, size = SCM_${VECTTYPE}_SIZE(v0);
    ScmObj se1;
    if (SCM_${VECTTYPE}P(operand)) {
        Scm${vecttype} *v1 = SCM_${VECTTYPE}(operand);
        ${itemtype} r, e0, e1;
        SIZECHK(dst, v0, v1);
        for (i=0; i<size; i++) {
            e0 = SCM_${VECTTYPE}_ELEMENTS(v0)[i];
            e1 = SCM_${VECTTYPE}_ELEMENTS(v1)[i];
            switch (op) {
              case SCM_UVECTOR_ADD:
                ${VECTTAG}ADD(r, e0, e1, clamp); break;
              case SCM_UVECTOR_SUB:
                ${VECTTAG}SUB(r, e0, e1, clamp); break;
              case SCM_UVECTOR_MUL:
                ${VECTTAG}MUL(r, e0, e1, clamp); break;
              case SCM_UVECTOR_DIV:
                ${VECTTAG}DIV(r, e0, e1); break;
              case SCM_UVECTOR_AND:
                ${VECTTAG}AND(r, e0, e1); break;
              case SCM_UVECTOR_IOR:
                ${VECTTAG}IOR(r, e0, e1); break;
              case SCM_UVECTOR_XOR:
                ${VECTTAG}XOR(r, e0, e1); break;
            }
            SCM_${VECTTYPE}_ELEMENTS(dst)[i] = r;
        }
    } else if (SCM_PAIRP(operand)) {
        ${itemtype} r, e0;
        SIZECHKL(operand, size, v0);
        for (i=0; i<size; i++, operand = SCM_CDR(operand)) {
            e0 = SCM_${VECTTYPE}_ELEMENTS(v0)[i];
            se1 = SCM_CAR(operand);
            switch (op) {
              case SCM_UVECTOR_ADD:
                ${VECTTAG}ADDOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_SUB:
                ${VECTTAG}SUBOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_MUL:
                ${VECTTAG}MULOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_DIV:
                ${VECTTAG}DIVOBJ(r, e0, se1); break;
              case SCM_UVECTOR_AND:
                ${VECTTAG}ANDOBJ(r, e0, se1); break;
              case SCM_UVECTOR_IOR:
                ${VECTTAG}IOROBJ(r, e0, se1); break;
              case SCM_UVECTOR_XOR:
                ${VECTTAG}XOROBJ(r, e0, se1); break;
            }
            SCM_${VECTTYPE}_ELEMENTS(dst)[i] = r;
        }
    } else if (SCM_VECTORP(operand)) {
        ${itemtype} r, e0;
        SIZECHKV(operand, size, v0);
        for (i=0; i<size; i++) {
            e0 = SCM_${VECTTYPE}_ELEMENTS(v0)[i];
            se1 = SCM_VECTOR_ELEMENTS(operand)[i];
            switch (op) {
              case SCM_UVECTOR_ADD:
                ${VECTTAG}ADDOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_SUB:
                ${VECTTAG}SUBOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_MUL:
                ${VECTTAG}MULOBJ(r, e0, se1, clamp); break;
              case SCM_UVECTOR_DIV:
                ${VECTTAG}DIVOBJ(r, e0, se1); break;
              case SCM_UVECTOR_AND:
                ${VECTTAG}ANDOBJ(r, e0, se1); break;
              case SCM_UVECTOR_IOR:
                ${VECTTAG}IOROBJ(r, e0, se1); break;
              case SCM_UVECTOR_XOR:
                ${VECTTAG}XOROBJ(r, e0, se1); break;
            }
            SCM_${VECTTYPE}_ELEMENTS(dst)[i] = r;
        }
    } else {
        ${itemtype} r, e0;
        SCM_ASSERT(SCM_${VECTTYPE}_SIZE(dst) == SCM_${VECTTYPE}_SIZE(v0));
        for (i=0; i<size; i++) {
            e0 = SCM_${VECTTYPE}_ELEMENTS(v0)[i];
            switch (op) {
              case SCM_UVECTOR_ADD:
                ${VECTTAG}ADDOBJ(r, e0, operand, clamp); break;
              case SCM_UVECTOR_SUB:
                ${VECTTAG}SUBOBJ(r, e0, operand, clamp); break;
              case SCM_UVECTOR_MUL:
                ${VECTTAG}MULOBJ(r, e0, operand, clamp); break;
              case SCM_UVECTOR_DIV:
                ${VECTTAG}DIVOBJ(r, e0, operand); break;
              case SCM_UVECTOR_AND:
                ${VECTTAG}ANDOBJ(r, e0, operand); break;
              case SCM_UVECTOR_IOR:
                ${VECTTAG}IOROBJ(r, e0, operand); break;
              case SCM_UVECTOR_XOR:
                ${VECTTAG}XOROBJ(r, e0, operand); break;
            }
            SCM_${VECTTYPE}_ELEMENTS(dst)[i] = r;
        }
    }
    return SCM_OBJ(dst);
}
EOF
}

binop s8
binop u8
binop s16
binop u16
binop s32
binop u32
binop s64
binop u64
binop f32
binop f64

#=================================================================
# Template for dot product
#

# common prologue for integer vector dot product
dotprod_prologue() {
    vecttype=$1
    VECTTYPE=$2
    itemtype=$3
    calctype=$4

    cat <<EOF
ScmObj Scm_${vecttype}DotProd(Scm${vecttype} *v0,
                              ScmObj v1)
{
    long val_int = 0;
    ScmObj val_big = SCM_FALSE;
    ${itemtype} *p0, *p1 = NULL;
    ScmObj s1, *ve1 = NULL;
    int i, len = SCM_${VECTTYPE}_SIZE(v0);
    p0 = SCM_${VECTTYPE}_ELEMENTS(v0);
    if (SCM_${VECTTYPE}P(v1)) {
        if (len != SCM_${VECTTYPE}_SIZE(v1)) {
            Scm_Error("Vector size doesn't match: %S and %S", v0, v1);
        }
        p1 = SCM_${VECTTYPE}_ELEMENTS(v1);
    } else if (SCM_PAIRP(v1) || SCM_NULLP(v1)) {
        SIZECHKL(v1, len, v0);
        s1 = v1;
    } else if (SCM_VECTORP(v1)) {
        SIZECHKV(v1, len, v0);
        ve1 = SCM_VECTOR_ELEMENTS(v1);
    } else {
        Scm_Error("bad type of object: %S: must be either a ${vecttag}vector, a vector or a list of numbers", v1);
    }
    for (i=0; i<len; i++, p0++) {
        ${calctype} sum, prod, e0 = *p0, e1, v;
        if (p1) e1 = *p1;
        else if (ve1) ${VECTTAG}UNBOX(e1, *ve1, SCM_UVECTOR_CLAMP_NONE);
        else ${VECTTAG}UNBOX(e1, SCM_CAR(s1), SCM_UVECTOR_CLAMP_NONE);
EOF
}

# common epilogue for integer vector dot product
dotprod_epilogue() {
    intboxer=$1
    
    cat <<EOF
      next:
        if (p1) p1++;
        else if (ve1) ve1++;
        else s1 = SCM_CDR(s1);
    }
    if (SCM_FALSEP(val_big)) return ${intboxer}(val_int);
    else return Scm_Add2(val_big, ${intboxer}(val_int));
}
EOF
}


# works for integer vectors whose element size is
# less than or equal to half word.
dotprod_small() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"
    calctype=$2
    ADDOV=$3
    MakeInt=$4

    dotprod_prologue $vecttype $VECTTYPE $itemtype $calctype
    cat <<EOF
        prod = e0 * e1; /* this never overflows */
        ${ADDOV}(sum, v, val_int, prod);
        if (!v) {
            val_int = sum;
            goto next;
        }
        /* overflow */
        if (!SCM_FALSEP(val_big)) {
            val_big = Scm_Add2(val_big, ${MakeInt}(val_int));
        } else {
            val_big = ${MakeInt}(val_int);
        }
        val_big = Scm_Add2(val_big, ${MakeInt}(prod));
        val_int = 0;
EOF
    dotprod_epilogue ${MakeInt}
}

# works for integer vectors whose element size is equal to the word.
dotprod_full() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"
    calctype=$2
    MULOV=$3
    ADDOV=$4
    MakeInt=$5

    dotprod_prologue $vecttype $VECTTYPE $itemtype $calctype
    cat <<EOF
        ${MULOV}(prod, v, e0, e1);
        if (v) {
            if (!SCM_FALSEP(val_big)) {
                val_big = Scm_Add2(val_big, ${MakeInt}(val_int));
            } else {
                val_big = ${MakeInt}(val_int);
            }
            val_big = Scm_Add2(val_big, Scm_Multiply2(${MakeInt}(e0), ${MakeInt}(e1)));
            val_int = 0;
            goto next;
        }
        ${ADDOV}(sum, v, prod, val_int);
        if (!v) {
            val_int = sum;
            goto next;
        }
        if (!SCM_FALSEP(val_big)) {
            val_big = Scm_Add2(val_big, ${MakeInt}(val_int));
        } else {
            val_big = ${MakeInt}(val_int);
        }
        val_big = Scm_Add2(val_big, ${MakeInt}(prod));
        val_int = 0;
EOF
    dotprod_epilogue ${MakeInt}
}

# works for alternative of 64bit vector on 32bit architecture
dotprod_scm() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"

    cat <<EOF
ScmObj Scm_${vecttype}DotProd(Scm${vecttype} *v0,
                              ScmObj v1)
{
    ScmObj val_big = SCM_MAKE_INT(0);
    ScmObj *p0, *p1, s1;
    int i, len = SCM_${VECTTYPE}_SIZE(v0);
    p0 = SCM_${VECTTYPE}_ELEMENTS(v0);
    if (SCM_${VECTTYPE}P(v1)) {
        if (len != SCM_${VECTTYPE}_SIZE(v1)) {
            Scm_Error("Vector size doesn't match: %S and %S", v0, v1);
        }
        p1 = SCM_${VECTTYPE}_ELEMENTS(v1);
        for (i=0; i<len; i++, p0++, p1++) {
            val_big = Scm_Add2(val_big, Scm_Multiply2(*p0, *p1));
        }
    } else if (SCM_PAIRP(v1) || SCM_NULLP(v1)) {
        SIZECHKL(v1, len, v0);
        for (i=0, s1=v1; i<len; i++, p0++, s1=SCM_CDR(s1)) {
            val_big = Scm_Add2(val_big, Scm_Multiply2(*p0, SCM_CAR(s1)));
        }
    } else if (SCM_VECTORP(v1)) {
        SIZECHKV(v1, len, v0);
        p1 = SCM_VECTOR_ELEMENTS(v1);
        for (i=0; i<len; i++, p0++, p1++) {
            val_big = Scm_Add2(val_big, Scm_Multiply2(*p0, *p1));
        }
    }
    return val_big;
}
EOF
}

dotprod_flo() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"

    cat <<EOF
ScmObj Scm_${vecttype}DotProd(Scm${vecttype} *v0,
                              ScmObj v1)
{
    double val = 0.0;
    ${itemtype} *p0, *p1 = NULL;
    int i, len = SCM_${VECTTYPE}_SIZE(v0);
    ScmObj s1, e1, *ve1;

    p0 = SCM_${VECTTYPE}_ELEMENTS(v0);

    if (SCM_${VECTTYPE}P(v1)) {
        if (len != SCM_${VECTTYPE}_SIZE(v1)) {
            Scm_Error("Vector size doesn't match: %S and %S", v0, v1);
        }
        p1 = SCM_${VECTTYPE}_ELEMENTS(v1);
        for (i=0 ; i<len; i++) val += (double)*p0++ * (double)*p1++;
    } else if (SCM_PAIRP(v1) || SCM_NULLP(v1)) {
        SIZECHKL(v1, len, v0);
        for (i=0, s1=v1; i<len; i++, s1=SCM_CDR(s1)) {
            val += (double)*p0++ * Scm_GetDouble(SCM_CAR(s1));
        }
    } else if (SCM_VECTORP(v1)) {
        SIZECHKV(v1, len, v0);
        ve1 = SCM_VECTOR_ELEMENTS(v1);
        for (i=0; i<len; i++) {
            val += (double)*p0++ * Scm_GetDouble(*ve1++);
        }
    } else {
        Scm_Error("bad type of object: %S: must be either a ${vecttag}vector, a vector or a list of numbers", v1);
    }
    return Scm_MakeFlonum(val);
}
EOF
}

dotprod_small s8  long   SADDOV Scm_MakeInteger
dotprod_small u8  u_long UADDOV Scm_MakeIntegerFromUI
dotprod_small s16 long   SADDOV Scm_MakeInteger
dotprod_small u16 u_long UADDOV Scm_MakeIntegerFromUI
echo "#if SIZEOF_LONG == 4"
dotprod_full  s32 long   SMULOV SADDOV Scm_MakeInteger
dotprod_full  u32 u_long UMULOV UADDOV Scm_MakeIntegerFromUI
dotprod_scm   s64
dotprod_scm   u64
echo "#else /* SIZEOF_LONG >= 4 */"
dotprod_small s32 long   SADDOV Scm_MakeInteger
dotprod_small u32 u_long UADDOV Scm_MakeIntegerFromUI
dotprod_full  s64 long   SMULOV SADDOV Scm_MakeInteger
dotprod_full  u64 u_long UMULOV UADDOV Scm_MakeIntegerFromUI
echo "#endif /* SIZEOF_LONG >= 4 */"

dotprod_flo f32
dotprod_flo f64

#=================================================================
# Template for range operation
#

# common pattern for range-check and clamp
rangeop() {
    vecttag=$1
    VECTTAG=`echo $vecttag | tr '[a-z]' '[A-Z]'`
    vecttype="${VECTTAG}Vector"
    VECTTYPE="${VECTTAG}VECTOR"
    itemtype="${VECTTAG}ELTTYPE"
    UNBOX="${VECTTAG}UNBOX"
    objtype=$2
    OBJCHKP=$3
    OBJINIT=$4
    COMPARE=$5
    NAME=$6
    ACTION=$7
    RETURN=$8

    cat <<EOF
ScmObj Scm_${vecttype}${NAME}(Scm${vecttype} *v0,
                              ScmObj min,
                              ScmObj max)
{
    int i, len = SCM_${VECTTYPE}_SIZE(v0);
    ${itemtype} *pmin = NULL, *pmax = NULL;
    ${itemtype} *elt = SCM_${VECTTYPE}_ELEMENTS(v0);
    ${objtype} omin = ${OBJINIT}, omax = ${OBJINIT};
    ScmObj smin = SCM_FALSE, smax = SCM_FALSE;
    ScmObj *vmin = NULL, *vmax = NULL;
    int minchk = TRUE, maxchk = TRUE;
    ${objtype} v;
    
    if (SCM_${VECTTYPE}P(min)) {
        if (SCM_${VECTTYPE}_SIZE(min) != len) {
            Scm_Error("Vector size doesn't match: %S and %S", v0, min);
        }
        pmin = SCM_${VECTTYPE}_ELEMENTS(min);
    } else if (SCM_PAIRP(min) || SCM_NULLP(min)) {
        smin = min;
        SIZECHKL(min, len, v0);
    } else if (SCM_VECTORP(min)) {
        SIZECHKV(min, len, v0);
        vmin = SCM_VECTOR_ELEMENTS(min);
    } else if (${OBJCHKP}(min)) {
        ${UNBOX}(omin, min, SCM_UVECTOR_CLAMP_BOTH);
    } else if (SCM_FALSEP(min)) {
        minchk = FALSE;
    } else {
        Scm_Error("Bad type of argument for min: %S", min);
    }
    if (SCM_${VECTTYPE}P(max)) {
        if (SCM_${VECTTYPE}_SIZE(max) != len) {
            Scm_Error("Vector size doesn't match: %S and %S", v0, max);
        }
        pmax = SCM_${VECTTYPE}_ELEMENTS(max);
    } else if (SCM_PAIRP(max) || SCM_NULLP(min)) {
        SIZECHKL(max, len, v0);
        smax = max;
    } else if (SCM_VECTORP(max)) {
        SIZECHKV(max, len, v0);
        vmax = SCM_VECTOR_ELEMENTS(max);
    } else if (${OBJCHKP}(max)) {
        ${UNBOX}(omax, max, SCM_UVECTOR_CLAMP_BOTH);
    } else if SCM_FALSEP(max) {
        maxchk = FALSE;
    } else {
        Scm_Error("Bad type of argument for max: %S", max);
    }        
    for (i=0; i<len; i++) {
        int r;
        if (minchk) {
            if (pmin) {
                ${COMPARE}(r, pmin[i], elt[i]);
                if (!r) ${ACTION}(i, elt[i], pmin[i]);
            } else if (vmin) {
                ${UNBOX}(v, vmin[i], SCM_UVECTOR_CLAMP_BOTH);
                ${COMPARE}(r, v, elt[i]);
                if (!r) ${ACTION}(i, elt[i], v);
            } else if (SCM_FALSEP(smin)) {
                ${COMPARE}(r, omin, elt[i]);
                if (!r) ${ACTION}(i, elt[i], omin);
            } else {
                ${UNBOX}(v, SCM_CAR(smin), SCM_UVECTOR_CLAMP_BOTH);
                ${COMPARE}(r, v, elt[i]);
                if (!r) ${ACTION}(i, elt[i], v);
                smin = SCM_CDR(smin);
            }
        }
        if (maxchk) {
            if (pmax) {
                ${COMPARE}(r, elt[i], pmax[i]);
                if (!r) ${ACTION}(i, elt[i], pmax[i]);
            } else if (vmax) {
                ${UNBOX}(v, vmax[i], SCM_UVECTOR_CLAMP_BOTH);
                ${COMPARE}(r, elt[i], v);
                if (!r) ${ACTION}(i, elt[i], v);
            } else if (SCM_FALSEP(smax)) {
                ${COMPARE}(r, elt[i], omax);
                if (!r) ${ACTION}(i, elt[i], omax);
            } else {
                ${UNBOX}(v, SCM_CAR(smax), SCM_UVECTOR_CLAMP_BOTH);
                ${COMPARE}(r, elt[i], v);
                if (!r) ${ACTION}(i, elt[i], v);
                smax = SCM_CDR(smax);
            }
        }
    }
    ${RETURN}(v0);
}
EOF
}

echo "#define NUMCMP(r, x, y)  (r) = (x) <= (y)"
echo "#define OBJCMP(r, x, y)  (r) = Scm_NumCmp(x, y) <= 0"
echo "#define RANGE_ACTION(i, e, o) return SCM_MAKE_INT(i)"
echo "#define RANGE_RETURN(v) return SCM_FALSE"
echo "#define CLAMP_ACTION(i, e, o)  (e) = (o)"
echo "#define CLAMP_RETURN(v)  return SCM_OBJ(v)"

gen_rangeop() {
    # range-check
    rangeop "$1" "$2" "$3" "$4" "$5" RangeCheck RANGE_ACTION RANGE_RETURN
    # clamp
    rangeop "$1" "$2" "$3" "$4" "$5" Clamp CLAMP_ACTION CLAMP_RETURN
}

gen_rangeop s8  long   SCM_EXACTP 0 NUMCMP
gen_rangeop u8  u_long SCM_EXACTP 0 NUMCMP
gen_rangeop s16 long   SCM_EXACTP 0 NUMCMP
gen_rangeop u16 u_long SCM_EXACTP 0 NUMCMP
gen_rangeop s32 long   SCM_EXACTP 0 NUMCMP
gen_rangeop u32 u_long SCM_EXACTP 0 NUMCMP
echo "#if SIZEOF_LONG == 4"
gen_rangeop s64 ScmObj SCM_EXACTP 0 OBJCMP
gen_rangeop u64 ScmObj SCM_EXACTP 0 OBJCMP
echo "#else /* SIZEOF_LONG >= 8 */"
gen_rangeop s64 long   SCM_EXACTP 0 NUMCMP
gen_rangeop u64 u_long SCM_EXACTP 0 NUMCMP
echo "#endif /* SIZEOF_LONG >= 8 */"
gen_rangeop f32 double SCM_REALP  0 NUMCMP
gen_rangeop f64 double SCM_REALP  0 NUMCMP
