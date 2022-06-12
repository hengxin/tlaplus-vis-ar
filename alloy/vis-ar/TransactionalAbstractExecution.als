module TransactionalHistory

sig Obj {}

abstract sig Op {
	obj: Obj,
	val: Int
}

sig Read,Write extends Op {}

sig EventId {}
abstract sig HEvent {
	id: EventId,
	op: Op,
}{
	all h : HEvent | (h.@id = id) => h = this // event ids are distinct
}

sig REvent extends HEvent {}{ op in Read }
sig WEvent extends HEvent {}{ op in Write }

sig Transaction {
	E : some HEvent,
	po: HEvent -> HEvent,
	VIS: set Transaction,
	AR: set Transaction
}{
	all e1, e2 : E | e1!=e2 => (e1->e2 in po or e2->e1 in po) // po is total	
	no po & ~po // po is antisymmetric
	no iden & po // po is irreflexive
	po in E->E // po only contains events from e	
	VIS in AR // vis is a subset of ar
}

fun HEventObj[x : Obj] : HEvent { {e : HEvent | e.op.obj = x } }
fun WEventObj[x : Obj] : WEvent { HEventObj[x] & WEvent }
fun REventObj[x : Obj] : REvent { HEventObj[x] & REvent }

fact WellFormedHistory {
	all e : HEvent | one E.e // Any HEvent belongs to one Transaction
	Op in HEvent.op   // All ops are associated with HEvents
	Obj in Op.obj  // All objs are associated with ops
	all t : Transaction | t not in t.^VIS  // Acyclic vis
	all t : Transaction | t not in t.^AR   // Acyclic ar
	no (iden & AR) and no (AR & ~AR) and all disj t1, t2 : Transaction | t1!=t2 => t1->t2 in AR or t2->t1 in AR // Ar is total
}

////////////////////////////////////////////////////////////////////////////////
// Baseline consistency model: Read Atomic

pred noNonRepeatableReads {
all t : Transaction | 
	all r1,r2 : t.E & REvent |
		// if same object is being read and r1 comes before r2
		((r1.op.obj = r2.op.obj) and (r1->r2 in t.po) and
		// and no write after r1 and before r2
		(no w : t.E & WEvent | (w.op.obj = r1.op.obj and ({r1->w} + {w->r2}) in t.po)))
		// then they will read the same value
		=> 	r1.op.val = r2.op.val
}

//check noNonRepeatableReads

fun max[R : HEvent->HEvent, A : set HEvent] : HEvent { {u : A | all v : A | v=u or v->u in R } }
fun min[R : HEvent->HEvent, A : set HEvent] : HEvent { {u : A | all v : A | v=u or u->v in R } }

// Internal consistency axiom
pred INT {
	all t : Transaction, e : t.E, x : Obj, n : Int |
  		let prevOpX = max[t.po, (t.po).e & HEventObj[x]].op | 
    	(reads[e.op, x, n] and some (t.po).e & HEventObj[x]) => accesses[prevOpX, x, n]
}

// True if op reads n from x or writes n to x
pred accesses[op : Op, x : Obj, n : Int] { op.obj=x and op.val=n }

// True if op reads n from x
pred reads[op : Op, x : Obj, n : Int] { op in Read and accesses[op, x, n] }

// run {noNonRepeatableReads and #Obj =1} for 3

fun committedWrite[t : Transaction, x : Obj] : Int {
    max[t.po, t.E & WEventObj[x]].op.val
}

fun overwrittenWrites[t : Transaction, x : Obj] : set Int {
    (t.E & WEventObj[x]).op.val - committedWrite[t, x]
}

pred noDirtyReads {
	all x : Obj | no t : Transaction |
 	(no t.E & WEventObj[x]) and 
	(some s : Transaction |  some ((t.E & REventObj[x]).op.val & overwrittenWrites[s, x]) - {0})
}

// External consistency axiom
pred EXT {
	all t : Transaction, x : Obj, n : Int |
    	TReads[t, x, n] => 
        	let WritesX = {s : Transaction | (some m : Int | TWrites[s, x, m]) } |
        	(no (VIS.t & WritesX) and n=0) or TWrites[(maxAR[VIS.t & WritesX]), x, n]
}

// In transaction t, the last write to object x was value n
pred TWrites[t : Transaction, x : Obj, n : Int] {
	let lastWriteX = max[t.po, t.E & WEventObj[x]].op |
		lastWriteX in Write and lastWriteX.obj=x and lastWriteX.val=n
}

// In transaction t, the first access to object x was a read of value n
pred TReads[t : Transaction, x : Obj, n : Int] {
	let firstOpX = min[t.po, t.E & HEventObj[x]].op |
		firstOpX in Read and firstOpX.obj=x and firstOpX.val=n
}

fun maxAR[T: set Transaction] : Transaction { {t : T | all s : T | s=t or s->t in AR} }


////////////////////////////////////////////////////////////////////////////////
// Stronger consistency model

pred TransVis { ^VIS in VIS }

pred NoConflict {
	all t,s : Transaction | 
		(some x : Obj | (t != s and (some m : Int | TWrites[t, x, m]) and (some m : Int | TWrites[s, x, m])))
		 => t->s in VIS or s->t in VIS
}

pred Prefix { AR.VIS in VIS }
pred TotalVis { no (iden & VIS) and no (VIS & ~VIS) and all disj t,s : Transaction | t->s in VIS or s->t in VIS}

pred CC { INT and EXT and TransVis }
pred PC { INT and EXT and Prefix }
pred PSI { INT and EXT and TransVis and NoConflict}
pred SI { INT and EXT and Prefix } 
pred SET { INT and EXT and TotalVis }

run CC for 4

