#!/usr/bin/env python3
"""
viz.py — Improved visualization for large poker trees.

Features:
 - SVG output (zoomable)
 - Collapse linear chains (default ON)
 - Prune branches by min amount, max depth, or max nodes
 - Option to keep only top-k children by amount at each branching
 - Color nodes by depth
 - Left->Right layout option

Usage examples:
    python viz.py tree_output.json -o tree.svg
    python viz.py tree_output.json -o tree.svg --rankdir LR --topk 10 --min-amount 1.0
    python viz.py tree_output.json -o tree.svg --max-depth 6 --collapse-chains

Requirements:
    pip install graphviz
    Graphviz (dot) installed and on PATH
"""

from __future__ import annotations
import json
import argparse
import os
import math
import random
from graphviz import Digraph
from typing import Any, Dict, Optional, List, Tuple

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def node_label(edge: Dict[str, Any], show_amount: bool = True) -> str:
    action = edge.get("action", "")
    amount = edge.get("amount", None)
    if show_amount and amount is not None:
        try:
            amt_s = f"{float(amount):.2f}"
        except Exception:
            amt_s = str(amount)
        return f"{action}\\n{amt_s}"
    else:
        return f"{action}"

def count_nodes(edge: Dict[str, Any]) -> int:
    # basic recursive count
    cnt = 1
    children = edge.get("children")
    if isinstance(children, list):
        for c in children:
            cnt += count_nodes(c)
    return cnt

def prune_children(children: List[Dict[str,Any]], min_amount: Optional[float], topk: Optional[int]) -> List[Dict[str,Any]]:
    if not children:
        return children
    # filter by min_amount
    if min_amount is not None:
        children = [c for c in children if (c.get("amount") is None or float(c.get("amount", 0)) >= min_amount)]
    # keep top-k by amount if requested
    if topk is not None and topk > 0 and len(children) > topk:
        # sort descending by amount (missing amounts go to -inf)
        def keyfn(c):
            try:
                return float(c.get("amount")) if c.get("amount") is not None else -math.inf
            except Exception:
                return -math.inf
        children_sorted = sorted(children, key=keyfn, reverse=True)
        # keep topk, but preserve original order for kept items
        top_set = set(id(c) for c in children_sorted[:topk])
        children = [c for c in children if id(c) in top_set]
    return children

def collapse_linear_chain(edge: Dict[str,Any]) -> Dict[str,Any]:
    """
    Collapse nodes that have a single child repeatedly into one node.
    The label concatenates actions/amounts separated by " → ".
    Returns a new edge dict.
    """
    seq_actions: List[str] = []
    seq_amounts: List[Optional[float]] = []
    node = edge
    visited = 0
    # follow while exactly one child (and child is list length 1)
    while True:
        seq_actions.append(str(node.get("action","")))
        seq_amounts.append(node.get("amount"))
        children = node.get("children")
        if not isinstance(children, list) or len(children) != 1:
            break
        node = children[0]
        visited += 1
        if visited > 5000:
            # safety break
            break
    # Build collapsed edge
    collapsed = {
        "action": " → ".join(seq_actions),
        "amount": seq_amounts[-1] if seq_amounts else None,
    }
    # attach remaining children from the final node (may be 0 or >1)
    final_children = node.get("children")
    collapsed["children"] = final_children if isinstance(final_children, list) else None
    return collapsed

def preprocess_tree(root: Dict[str,Any],
                    collapse_chains: bool,
                    min_amount: Optional[float],
                    topk: Optional[int],
                    max_depth: Optional[int],
                    max_nodes: Optional[int]) -> Dict[str,Any]:
    """
    Returns a processed copy suitable for rendering.
    Prunes and optionally collapses chains.
    Note: this function tries to respect max_nodes by truncating large sibling lists,
    but it does not do a global optimal selection (that would be expensive).
    """
    # We'll perform a BFS/DFS traversal and build a new tree
    # Keep a running node count and stop expanding when max_nodes reached.
    nodes_used = 0
    def traverse(node: Dict[str,Any], depth: int) -> Optional[Dict[str,Any]]:
        nonlocal nodes_used
        if max_nodes is not None and nodes_used >= max_nodes:
            return None
        # prune by min_amount
        if min_amount is not None:
            amt = node.get("amount")
            try:
                if amt is not None and float(amt) < min_amount:
                    return None
            except Exception:
                pass
        if max_depth is not None and depth > max_depth:
            return None
        nodes_used += 1
        # make shallow copy
        new_node = {k:v for k,v in node.items() if k != "children"}
        children = node.get("children")
        if isinstance(children, list) and children:
            # prune / topk
            pruned = prune_children(children, min_amount, topk)
            new_children: List[Dict[str,Any]] = []
            for c in pruned:
                processed = traverse(c, depth+1)
                if processed is not None:
                    new_children.append(processed)
                if max_nodes is not None and nodes_used >= max_nodes:
                    break
            new_node["children"] = new_children if new_children else None
        else:
            new_node["children"] = None
        # optionally collapse linear chain immediately after child processing
        if collapse_chains:
            # if this node has a single child, and that child has a single child, collapse them
            while True:
                ch = new_node.get("children")
                if isinstance(ch, list) and len(ch) == 1:
                    child = ch[0]
                    # merge child into parent (concatenate labels)
                    # join actions
                    a1 = str(new_node.get("action",""))
                    a2 = str(child.get("action",""))
                    new_node["action"] = f"{a1} → {a2}"
                    # keep child's amount as representative
                    new_node["amount"] = child.get("amount")
                    # attach grand-children
                    new_node["children"] = child.get("children")
                    # loop again in case more chain
                else:
                    break
        return new_node
    res = traverse(root, 0)
    return res if res is not None else {}

def add_edge_nodes(g: Digraph, edge: Dict[str, Any], parent_id: Optional[str], counter: Dict[str,int], max_nodes: Optional[int]) -> Optional[str]:
    """
    Adds nodes recursively to Graphviz digraph. Returns this node's id or None if skipped.
    """
    if max_nodes is not None and counter["n"] >= max_nodes:
        return None
    counter["n"] += 1
    node_id = f"e{counter['n']}"

    label = node_label(edge, show_amount=True)
    depth = edge.get("_depth", 0)
    color = depth_color(depth)
    # node style: fillcolor set by depth; make SVG-friendly small font
    g.node(node_id, label=label, shape="box", fontsize="10", fontname="Helvetica",
           style="rounded,filled", fillcolor=color)

    if parent_id is not None:
        g.edge(parent_id, node_id)

    children = edge.get("children", None)
    if isinstance(children, list):
        for c in children:
            # pass depth info to children so color can be computed
            if isinstance(c, dict):
                c["_depth"] = depth + 1
            child_id = add_edge_nodes(g, c, node_id, counter, max_nodes)
            if child_id is None:
                break
    return node_id

def depth_color(depth: int) -> str:
    """
    Return a soft color string for a depth (SVG friendly).
    We'll vary hue with depth to get distinct bands.
    """
    # simple HSL mapping -> convert to hex approximate
    # keep saturation/lightness constant
    hue = (depth * 37) % 360  # step hue per depth
    s = 60
    l = 92
    # convert hsl to rgb roughly (use formula)
    h = hue / 360.0
    c = (1 - abs(2*(l/100) - 1)) * (s/100)
    x = c * (1 - abs(((h*6) % 2) - 1))
    m = (l/100) - c/2
    r1,g1,b1 = 0,0,0
    if 0 <= h < 1/6:
        r1,g1,b1 = c,x,0
    elif 1/6 <= h < 2/6:
        r1,g1,b1 = x,c,0
    elif 2/6 <= h < 3/6:
        r1,g1,b1 = 0,c,x
    elif 3/6 <= h < 4/6:
        r1,g1,b1 = 0,x,c
    elif 4/6 <= h < 5/6:
        r1,g1,b1 = x,0,c
    else:
        r1,g1,b1 = c,0,x
    r = int((r1 + m) * 255)
    g = int((g1 + m) * 255)
    b = int((b1 + m) * 255)
    return f"#{r:02x}{g:02x}{b:02x}"

def render_tree(root_edge: Dict[str,Any], outpath: str, fmt: str = "svg", rankdir: str = "TB", engine: str = "dot",
                collapse_chains: bool = True, min_amount: Optional[float] = None, topk: Optional[int] = None,
                max_depth: Optional[int] = None, max_nodes: Optional[int] = None):
    # Preprocess
    processed = preprocess_tree(root_edge, collapse_chains=collapse_chains, min_amount=min_amount,
                                topk=topk, max_depth=max_depth, max_nodes=max_nodes)
    # set depth markers for colors
    def set_depths(node: Dict[str,Any], depth: int):
        node["_depth"] = depth
        ch = node.get("children")
        if isinstance(ch, list):
            for c in ch:
                set_depths(c, depth+1)
    set_depths(processed, 0)

    g = Digraph(name="PokerTree", format=fmt, engine=engine)
    g.attr(rankdir=rankdir)
    g.attr(splines="ortho")
    g.attr(nodesep="0.2")
    g.attr(ranksep="0.5")
    g.attr("node", shape="box")

    counter = {"n": 0}
    add_edge_nodes(g, processed, None, counter, max_nodes)

    # Ensure output dir exists
    outdir = os.path.dirname(os.path.abspath(outpath))
    if outdir and not os.path.exists(outdir):
        os.makedirs(outdir, exist_ok=True)

    filename_no_ext = os.path.splitext(os.path.basename(outpath))[0]
    g.render(filename=os.path.join(outdir, filename_no_ext), cleanup=True)
    print(f"Rendered tree to {outpath} (nodes rendered ≈ {counter['n']})")

def main():
    p = argparse.ArgumentParser(description="Visualize (large) poker tree JSON with Graphviz (pruning + collapsing)")
    p.add_argument("json_file", help="JSON file generated by Zig (tree_output.json)")
    p.add_argument("-o", "--out", default="tree.svg", help="Output file (svg/png/pdf). Use .svg for zoomable output.")
    p.add_argument("--engine", default="dot", choices=["dot","neato","fdp","sfdp","twopi","circo"], help="Graphviz engine.")
    p.add_argument("--rankdir", default="TB", choices=["TB","LR"], help="TB (top->bottom) or LR (left->right).")
    p.add_argument("--collapse-chains", dest="collapse_chains", action="store_true", default=True, help="Collapse linear single-child chains.")
    p.add_argument("--no-collapse-chains", dest="collapse_chains", action="store_false", help="Disable chain collapsing.")
    p.add_argument("--min-amount", type=float, default=None, help="Prune children with amount < MIN.")
    p.add_argument("--topk", type=int, default=None, help="Keep only top-K children by amount at each branching.")
    p.add_argument("--max-depth", type=int, default=None, help="Do not expand past this depth.")
    p.add_argument("--max-nodes", type=int, default=None, help="Upper bound on rendered nodes (approx).")
    args = p.parse_args()

    data = load_json(args.json_file)
    root = data
    if isinstance(data, list):
        if len(data) == 0:
            raise SystemExit("Input JSON array is empty.")
        root = data[0]

    # detect fmt from out extension
    fmt = os.path.splitext(args.out)[1].lstrip(".").lower()
    if fmt == "":
        fmt = "svg"
        args.out = args.out + ".svg"

    render_tree(root, args.out, fmt=fmt, rankdir=args.rankdir, engine=args.engine,
                collapse_chains=args.collapse_chains, min_amount=args.min_amount,
                topk=args.topk, max_depth=args.max_depth, max_nodes=args.max_nodes)

if __name__ == "__main__":
    main()
