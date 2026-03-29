---
layout: post
title: Intuiting Pratt parsing
author: Louis Baragwanath
image: /assets/img/pratt/ast.png
---

You already know that `a + b * c + d` is calculated as
`a + (b * c) + d`. But how do you encode that knowledge precisely enough
for a machine to act on it?

The most common solution employed by compilers is to make use of a tree
known as an *abstract syntax tree*. In an AST, each operator sits above
its operands, and evaluation works bottom-up: resolve the children, then
apply the operation.

         +
        / \
       +   d
      / \
     a   *
        / \
       b   c

This tree encodes the desired ordering `(a + (b * c)) + d` in a format
that is very convenient to work with programmatically.

But of course, people (for the most part) don't write programs as trees.
This means we face the problem of *deriving* this structure from flat
text.

This is known as parsing. It has been the focus of decades of computer
science research. It has also, in many cases, been wildly
overcomplicated.

## Simplifying

The difficulty in parsing lies with mixed precedence. To be precise,
cases where precedence changes direction. Let's imagine our users only
ever wrote programs of either increasing or decreasing precedence. What
would that mean for our tree representation?

In the case of decreasing precedence, we repeatedly evaluate the
leftmost operator as it is higher precedence - multiplication before
addition, addition before comparison, and so on. The first operator sits
deepest in the tree, the last the shallowest. The resulting tree is
*left-leaning*.

    Decreasing

           <
          / \
         +   d
        / \
       *   c
      / \
     a   b

You can imagine what happens when precedence is increasing. It's the
exact opposite: the leftmost operator is now the shallowest and the
rightmost the deepest, as each operator depends on the result to its
right. The tree is *right-leaning*.

    Increasing

       >
      / \
     a   +
        / \
       b   *
          / \
         c   d

Now, what is the most reasonable encoding of equal precedence?

It depends on the operation. Convention favours a left-to-right
evaluation for arithmetic, known as *left associativity*. Some language
features favour the opposite: assignment in C, for instance, is right
associative.

Let's suppose (for now) that all operators are left associative. This is
represented by a left-leaning tree, as the leftmost operator must be
evaluated earlier and therefore rests deeper in the tree.

We should refine our definitions accordingly. Given a sequence of
operators, let `x_i` be the precedence of the `i`th operator:

-   Decreasing: *weakly* decreasing - `x_i >= x_{i+1}`. This now
    includes the case of equal precedence.
-   Increasing: *strictly* increasing - `x_i < x_{i+1}`.

This means any two equal-precedence operators are encoded exactly like
two decreasing ones.

## Extending

A natural continuation is to consider expressions with exactly one
change in direction. We'll focus on the more interesting of the two
resulting cases: a transition from increasing to decreasing precedence.
The reverse simply continues a right-leaning tree from the tip of the
existing left-leaning.

Consider the expression `I = (a > b + c * d)`, given by the tree below.

       >
      / \
     a   +
        / \
       b   *
          / \
         c   d

The tree is right-leaning, as expected for increasing precedence. Now,
suppose we extend `I` with a new operator whose precedence is equal to
or less than `*`. This would mean the increasing property no longer
holds, and so continuing a right-leaning tree would produce an incorrect
encoding.

We need a left-leaning tree somewhere, but where? The visualisation of
each possible precedence level for the new operator begins to reveal a
pattern:

    [I] * e:

       >
      / \
     a   +
        / \
       b   *
          / \
         *   e
        / \
       c   d

    [I] + e:

       >
      / \
     a   +
        / \
       +   e
      / \
     b   *
        / \
       c   d

    [I] == e:

         ==
        /  \
       >    e
      / \
     a   +
        / \
       b   *
          / \
         c   d

The left-leaning tree starts at the first place it can: at an operator
of equal or lesser precedence. This lower precedence operator must
evaluate later than *at least* the current one, but there could be
several prior operators that also must evaluate first. Those operators
are found along the spine of the right-leaning tree.

> The `==` case is the clearest example. All previous operators are
> higher precedence than `==`, so the entire spine of the tree must
> evaluate first, and therefore must be its left child.

The observation is as follows: when we encounter a transition operator,
we must walk back up the spine, collecting every operator that evaluates
first. That collected chain - a right-leaning subtree - becomes the
left child of the new operator, which starts a left-leaning tree of its
own.

Since any expression is just a sequence of these transitions, this is
all we need. This walk-back procedure *is* Pratt parsing.

## Parsing

We can hopefully make things a little more concrete with some
pseudocode, extending the right-leaning case to handle a transition as
we did earlier.

### Right Leaning
{: style="margin-top: 1.5em;"}

A right-leaning tree can be built by recursing onto ourselves and then
building the tree bottom up.

    def parse():
        left = leaf()

        if peek() is not None:
            op = advance()
            right = parse()
            return Node(op, left, right)

        return left

`parse()` first defers to `leaf()` to handle a literal such as `a`,
consuming it from the token stream before checking the next token with
`peek()`. The next token (an operator for a valid program) is consumed
by `advance()` which moves the parser to the next token. `parse()`
finally calls itself for the right-hand side.

The parser advances through the tokens as it recurses, and constructs
the tree as it returns. For our earlier tree `[I]`:

    -- Down: advance

    (1) parse(0)
        a [>] b  +  c  *  d

    (2) parse(prec(>))
        a  >  b [+] c  *  d

    (3) parse(prec(+))
        a  >  b  +  c [*] d

    (4) parse(prec(*))
        a  >  b  +  c  *  d [None]


    -- Up: build

    (4)  d

    (3) [*]
        / \
       c   d

    (2) [+]
        / \
       b   *
          / \
         c   d

    (1) [>]
        / \
       a   +
          / \
         b   *
            / \
           c   d

The use of recursion is how we will backtrack to find a continuation
point.

Until then, our parser produces incorrect trees for decreasing
precedence. To prevent parsing tokens we shouldn't, we can forward the
current precedence to the recursive child call:

    def parse(prev_prec=0):
        left = leaf()

        if peek() is not None and prec(peek()) > prev_prec:
            op = advance()
            right = parse(prec(op))
            return Node(op, left, right)

        return left

This works, but we can simplify by giving end-of-file its own token with
the lowest precedence - `peek()` would cause the condition to fail
naturally, letting us drop the null check:

    def parse(prev_prec=0):
        left = leaf()

        if prec(peek()) > prev_prec:
            op = advance()
            right = parse(prec(op))
            return Node(op, left, right)

        return left

### Left Leaning
{: style="margin-top: 1.5em;"}

As `parse()` recurses, it pushes a frame onto the call stack with the
left child and minimum precedence. The call stack, representing the
yet-to-be-built spine, is always of increasing precedence.

This means that when unwinding, we visit each level in decreasing order.
So, the first level where `peek()` can bind is also the correct level:
every level above is strictly lower in precedence, and we already know
it can't go deeper because `parse()` wouldn't have returned. The greedy
choice is the only correct choice.

But `if` is only capable of taking that greedy choice *once* - we need
to take it every time, because anything else is incorrect. So, we
replace `if` with `while`:

    def parse(prev_prec=0):
        left = leaf()

        while prec(peek()) > prev_prec:
            op = advance()
            right = parse(prec(op))
            left = Node(op, left, right)

        return left

This is the complete Pratt parser. The `while` loop is the walkback
procedure we described earlier: when a transition operator appears,
`parse()` returns up the call stack until it finds the right level, then
the loop consumes it and continues with the left-leaning subtree.

Here's the trace `[I] * e`, where `I = a > b + c * d`:

    -- Down: advance
    (1) a [>] b  +  c  *  d  *  e
    (2) a  >  b [+] c  *  d  *  e
    (3) a  >  b  +  c [*] d  *  e
    (4) a  >  b  +  c  *  d [*] e  FAIL

    -- Up: build

    (4)  d

    (3)  iteration 1:
         [*]
         / \
        c   d

         iteration 2:
         [*]
         / \
        *   e
       / \
      c   d

    (2) [+]
        / \
       b   *
          / \
         *   e
        / \
       c   d

    (1) [>]
        / \
       a   +
          / \
         b   *
            / \
           *   e
          / \
         c   d

The left-leaning subtree `(c * d) * e` is built entirely within frame
3's `while` loop.

### Right Associativity

In practice every operator has two types of precedence: left and right.
Pratt refers to this as left and right binding power, or LBP and RBP.
All of our operators so far have an equal LBP and RBP.

An operator's LBP determines how strongly it attracts the expression to
its left - this is what `peek()` checks in the `while` condition. Its
RBP determines how strongly it attracts the expression to its right -
this is what gets passed as `prev_prec` to the recursive call.

For left-associative operators, LBP and RBP are equal. When two `*`
operators meet, the second `*`'s LBP is not greater than the first `*`'s
RBP, so `parse()` does not recurse but instead loops at the same level
to build left.

We want the opposite for right-associative operators. `a = b = c` should
parse as `a = (b = c)`. The second `=` *should* be consumed by the
recursive call, not by the loop. We can achieve this by setting RBP
lower than LBP - the recursive child's precedence threshold is low
enough that a consecutive operator still passes the `>` check and gets
consumed deeper.

    def parse(prev_prec=0):
        left = leaf()

        while lbp(peek()) > prev_prec:
            op = advance()
            right = parse(rbp(op))
            left = Node(op, left, right)

        return left

To ensure this, we set `rbp = lbp` for left-associative operators, and
`rbp = lbp - 1` for right-associative.

## Summary

I've often found Pratt parsing to be presented as if it were a clever
trick. Well, it is, but with a very simple geometric intuition: trees
are either left-leaning or right-leaning depending on precedence. When
precedence drops, walk back up the spine until you find where the new
operator belongs.

I've read many articles on the same topic but never found it presented
this way - hopefully `N + 1` is of help to someone.
