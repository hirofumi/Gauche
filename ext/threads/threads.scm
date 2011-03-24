;;;
;;; threads.scm - thread related procedures.  to be autoloaded
;;;  
;;;   Copyright (c) 2000-2010  Shiro Kawai  <shiro@acm.org>
;;;   
;;;   Redistribution and use in source and binary forms, with or without
;;;   modification, are permitted provided that the following conditions
;;;   are met:
;;;   
;;;   1. Redistributions of source code must retain the above copyright
;;;      notice, this list of conditions and the following disclaimer.
;;;  
;;;   2. Redistributions in binary form must reproduce the above copyright
;;;      notice, this list of conditions and the following disclaimer in the
;;;      documentation and/or other materials provided with the distribution.
;;;  
;;;   3. Neither the name of the authors nor the names of its contributors
;;;      may be used to endorse or promote products derived from this
;;;      software without specific prior written permission.
;;;  
;;;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;;   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;;   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;;   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;;   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;;   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;;   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;  

(define-module gauche.threads
  (use gauche.record)
  (export gauche-thread-type

          thread? make-thread thread-name thread-specific-set! thread-specific
          thread-state thread-start! thread-yield! thread-sleep!
          thread-join! thread-terminate! thread-stop! thread-cont!

          mutex? make-mutex mutex-name mutex-state
          mutex-specific-set! mutex-specific
          with-locking-mutex mutex-lock! mutex-unlock!

          condition-variable? make-condition-variable condition-variable-name
          condition-variable-specific condition-variable-specific-set!
          condition-variable-signal! condition-variable-broadcast!

          join-timeout-exception? abandoned-mutex-exception?
          terminated-thread-exception? uncaught-exception?
          uncaught-exception-reason

          atom atom-ref atomic atomic-update!))
(select-module gauche.threads)

(inline-stub
 "#include \"threads.h\""

 (declcode
  "extern void Scm_Init_mutex(ScmModule*);"
  "extern void Scm_Init_threads(ScmModule*);")

 (initcode
  "Scm_Init_threads(mod);"
  "Scm_Init_mutex(mod);"))

;;===============================================================
;; System query
;;

(inline-stub
 (define-cproc gauche-thread-type ()
   (.if "defined(GAUCHE_USE_PTHREADS)"
        (result 'pthread)
        (result 'none))))

;;===============================================================
;; Thread
;;

(define (thread? obj) (is-a? obj <thread>))

(define (thread-name thread)
  (check-arg thread? thread)
  (slot-ref thread 'name))

(define (thread-specific-set! thread value)
  (check-arg thread? thread)
  (slot-set! thread 'specific value))

(define thread-specific
  (getter-with-setter
   (lambda (thread)
     (check-arg thread? thread)
     (slot-ref thread 'specific))
   thread-specific-set!))

(inline-stub
 (define-cproc thread-state (vm::<thread>)
   (case (-> vm state)
     [(SCM_VM_NEW)       (result 'new)]
     [(SCM_VM_RUNNABLE)  (result 'runnable)]
     [(SCM_VM_STOPPED)   (result 'stopped)]
     [(SCM_VM_TERMINATED)(result 'terminated)]
     [else (Scm_Error "[internal] thread state has invalid value: %d"
                      (-> vm state))]))

 (define-cproc make-thread (thunk::<procedure> :optional (name #f))
   Scm_MakeThread)

 (define-cproc thread-start! (vm::<thread>) Scm_ThreadStart)

 (define-cproc thread-yield! () ::<void> Scm_YieldCPU)

 (define-cproc thread-sleep! (timeout) Scm_ThreadSleep)

 (define-cproc thread-join! (vm::<thread> :optional (timeout #f) timeout-val)
   Scm_ThreadJoin)

 (define-cproc thread-terminate! (vm::<thread>) Scm_ThreadTerminate)

 (define-cproc thread-stop! (target::<thread>
                             :optional (timeout #f) (timeout-val #f))
   Scm_ThreadStop)

 (define-cproc thread-cont! (target::<thread>) Scm_ThreadCont)
 ) 

;;===============================================================
;; Mutex
;;

(define (mutex? obj)  (is-a? obj <mutex>))

(define (mutex-name mutex)
  (check-arg mutex? mutex)
  (slot-ref mutex 'name))

(define (mutex-state mutex)
  (check-arg mutex? mutex)
  (slot-ref mutex 'state))

(define (mutex-specific-set! mutex value)
  (check-arg mutex? mutex)
  (slot-set! mutex 'specific value))

(define mutex-specific
  (getter-with-setter
   (lambda (mutex)
     (check-arg mutex? mutex)
     (slot-ref mutex 'specific))
   mutex-specific-set!))

(define (with-locking-mutex mutex thunk)
  (dynamic-wind
   (lambda () (mutex-lock! mutex))
   thunk
   (lambda () (mutex-unlock! mutex))))

(inline-stub
 (define-cproc make-mutex (:optional (name #f)) Scm_MakeMutex)

 (define-cise-stmt with-mutex
   [(_ mutex . form)
    `(begin
       (cast void (SCM_INTERNAL_MUTEX_LOCK ,mutex))
       ,@form
       (cast void (SCM_INTERNAL_MUTEX_UNLOCK ,mutex)))])

 (define-cproc mutex-lock! (mutex::<mutex> :optional (timeout #f) thread)
   (let* ([owner::ScmVM* NULL])
     (cond [(SCM_VMP thread) (set! owner (SCM_VM thread))]
           [(SCM_UNBOUNDP thread) (set! owner (Scm_VM))]
           [(not (SCM_FALSEP thread)) (SCM_TYPE_ERROR thread "thread or #f")])
     (result (Scm_MutexLock mutex timeout owner))))
 
 (define-cproc mutex-unlock! (mutex::<mutex> :optional (cv #f) (timeout #f))
   (let* ([cond::ScmConditionVariable* NULL])
     (cond [(SCM_CONDITION_VARIABLE_P cv) (set! cond (SCM_CONDITION_VARIABLE cv))]
           [(not (SCM_FALSEP cv)) (SCM_TYPE_ERROR cv "condition variale or #f")])
     (result (Scm_MutexUnlock mutex cond timeout))))
 )

;;===============================================================
;; Condition variable
;;

(define (condition-variable? obj) (is-a? obj <condition-variable>))

(define (condition-variable-name cv)
  (check-arg condition-variable? cv)
  (slot-ref cv 'name))

(define (condition-variable-specific-set! cv value)
  (check-arg condition-variable? cv)
  (slot-set! cv 'specific value))

(define condition-variable-specific
  (getter-with-setter
   (lambda (cv)
     (check-arg condition-variable? cv)
     (slot-ref cv 'specific))
   condition-variable-specific-set!))

(inline-stub
  (define-cproc make-condition-variable (:optional (name #f))
    Scm_MakeConditionVariable)

  (define-cproc condition-variable-signal! (cv::<condition-variable>)
    Scm_ConditionVariableSignal)

  (define-cproc condition-variable-broadcast! (cv::<condition-variable>)
    Scm_ConditionVariableBroadcast)
  )  
     
;;===============================================================
;; Exceptions
;;

(define (join-timeout-exception? obj)
  (is-a? obj <join-timeout-exception>))

(define (abandoned-mutex-exception? obj)
  (is-a? obj <abandoned-mutex-exception>))

(define (terminated-thread-exception? obj)
  (is-a? obj <terminated-thread-exception>))

(define (uncaught-exception? obj)
  (is-a? obj <uncaught-exception>))

(define (uncaught-exception-reason exc)
  (check-arg uncaught-exception? exc)
  (slot-ref exc 'reason))

;;===============================================================
;; Atom
;;

(define (atom . vals)
  (define m (make-mutex))
  (let-syntax ([with-lock
                (syntax-rules ()
                  [(_ timeout timeout-val . form)
                   (unwind-protect
                       (if (mutex-lock! m timeout)
                         (begin . form)
                         timeout-val)
                     (when (eq? (mutex-state m) (current-thread))
                       (mutex-unlock! m)))])])
    (define (atom-internal msg proc timeout timeout-val)
      (case msg
        [(apply)
         (with-lock timeout timeout-val (apply proc vals))]
        [(update)
         (with-lock timeout timeout-val
                    (call-with-values (cut apply proc vals)
                      (^ vs
                        (unless (= (length vs) (length vals))
                          (errorf "atomic-update!: procedure returned wrong \
                                   number of values (~a, while ~a expected)"
                                  (length vs) (length vals)))
                        (set! vals vs)
                        (apply values vals))))]
        [else (error "Unknown message to an atom" msg)]))
    atom-internal))

(define (atomic atom proc :optional (timeout #f) (timeout-val #f))
  (atom 'apply proc timeout timeout-val))

(define (atomic-update! atom proc :optional (timeout #f) (timeout-val #f))
  (atom 'update proc timeout timeout-val))

(define (atom-ref atom :optional (index 0) (timeout #f) (timeout-val #f))
  (atom 'apply (^ xs (list-ref xs index)) timeout timeout-val))
