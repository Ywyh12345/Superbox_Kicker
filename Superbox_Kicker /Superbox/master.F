c******************************************************************
c
c     Main program
c
      subroutine master (cstep,mstep)

      include 'super.cb'

      integer   i,j,k
      integer   step,cstep,mstep
      real      time1,time2,t1,t2,tr,tf,tp
      real      dt_check
      real      rhomax_ref, rmean_ref, rc_grid, rm_grid, rho1 
      
c
c     Be sure you have removed the stop file, otherwise the
c     program will stop after one single step !
c
c     Fourier-transformation of the Greensfunction:
c     =============================================
c
      tr=0.0
      tf=0.0
      tp=0.0

#ifdef GNUF77
      call CPU_TIME(t1)
#endif
      call geth                  ! transformation of the Greensfunct.
      
#ifdef GNUF77
      call CPU_TIME(t2)         ! see: geth.f and fft.f
#endif

      do i = 1,5 
        write( 6,* ) i, h(i,0,0), h(i,1,0), h(i,1,2) 
      end do 



      t2=t2-t1                   ! this is done only once at the
      write(unit,'(a,f20.10,a)') ! beginning of the simulation
     $     'geth:',t2,' sec'     ! and stored in the array h
c
c     Set the focus of the grids :
c     ============================
c
      if (origin .eq. 0) then   ! focus is on center of mass
         do i = 1,gnum
            do j = 1,6
               dgcms(j,i) = gcms(j,i)
            enddo
         enddo
      else           ! focus is on center of density
         call getflags (dgcms) 
      endif  


c
c       Obtain reference grid-averaged densities : find maximum value;
c       for variable time-step.
c
      rhomax_ref = -1. 
c

      do k = 1,gnum  
         if (gstno(k) .gt. 0) call getrho (k) 
         do j = 1,5 
          rhomax_ref = max(rhomax_ref,rhomax(k,j))
         end do  
      end do 

c
c       Check if user-defined time-step is reasonable: Use etimate
c       of crossing time tcr = SQRT(3pi/(16Grho)); G==2. !!

c++     Changes - define a dynamical timestep (cmb 04.03.1999). 

      dt_check = sqrt( 3.*pi / 16. / (2.*rhomax_ref) ) / sct 

c     Play it safe: divide by arbitrary factor 'pi' + divide by
c     the cell crossing-time of the inner grid : cmb 11.06.1999

      dt_check = dt_check/3.14159 * ( 1./2**m ) 

      write(unit,* ) 
      write(unit,90210)
     +     ' SUPERBOX proposes time step: ',dt_check, tunit 
      write(unit,90210) ' User had input: ', dt(1)/sct, tunit

      if( ih(12) .gt. 0 .and. fh(31,1) .lt. sct*dt_check ) 
     &                             dt(1) = min(sct*dt_check, dt(1) )

      write(unit,90211)
     +     ' Using dt= ',dt(1)/sct, tunit

      ! Make sure the timestep is expressed in m.u. for all galaxies : 

      do i = 1,gnum 
         dt(i) = dt(1) 
         fh(4,i) = dt(i)/sct 
c     For varying time-steps: split dt evenly and store: 
 
         halfdt(i,1) = dt(i)/2.
         halfdt(i,2) = dt(i)/2.
      end do 
     
c     Starting the simulation :
c     =============================
c
#ifdef GNUF77
      call CPU_TIME(time1)
#endif
c
      do step = cstep,mstep     ! begin of the time-step loop
c     
c     Initialize some variables :
c     ===========================
c
         ekin  = 0.0            ! total kin. energy
         epot  = 0.0            ! total pot. energy
         lx    = 0.0            ! total angular momentum in x
         ly    = 0.0            ! total angular momentum in y
         lz    = 0.0            ! total angular momnetum in z
c
         do i = 1,gnum
            do j = 1,6
               hcms(j,i) = 0.0
            enddo
            gekin(i) = 0.0      ! kin. energy of galaxy i
            gepot(i) = 0.0      ! pot. energy of galaxy i
            lgx(i)   = 0.0      ! angular mom. in x of gal. i
            lgy(i)   = 0.0      ! angular mom. in y of gal. i
            lgz(i)   = 0.0      ! angular mom. in z of gal. i
         enddo
c
c     Start the galaxy loop of each step :
c     ====================================
c
         do k = 1,gnum         ! begin galaxy-loop
c
c     Get the mass-density in each mesh-point for all 5 grids 
c     of galaxy k :
c     =======================================================
c
      
#ifdef GNUF77
      call CPU_TIME(t1)
#endif 
            if (gstno(k) .gt. 0) call getrho (k) ! see: getrho.f
#ifdef GNUF77      
      call CPU_TIME(t2)
#endif
            tr=tr+t2-t1
c
c     Calculating the potential of galaxy k for all 5 grids :
c     =======================================================
c
c     via discrete fast fourier transformation
c


#ifdef GNUF77      
       call CPU_TIME(t1)
#endif     
            call getpxx (1)     ! see: getxx.f and fft.f
            call getpxx (2) 
            call getpxx (3) 
            call getpxx (4)
            call getpxx (5)

#ifdef GNUF77      
       call CPU_TIME(t2)
#endif   
            tf=tf+t2-t1
c
c     Calculating the acceleration for each particle of all galaxies
c     out of the potential of galaxy k and update the velocities :
c     ==============================================================
c
c     via discrete differentiating the potential in the neighbouring 
c     mesh-points to second order and updating the velocities of all 
c     particles via leap-frog integration
c
#ifdef GNUF77      
       call CPU_TIME(t1)
#endif 
c
c     Compute the new timestep : 
c
            if (ih(12).GT.0) then
              dt(k) = halfdt(k,1) + halfdt(k,2)
              fh(4,k) = dt(k)/sct 
            end if
c

            call pusher1 (k,step) ! see: pusher.f
#ifdef GNUF77      
       call CPU_TIME(t2)
#endif 
            tp=tp+t2-t1
c     
         enddo                  ! end galaxy-loop
c
c       Skip timestep adjustment unless allowed.
c
         if (ih(12).GT.0) then
c
c       Choose new timestep according to local density maximum, 
c       if want variable time step (note that an input time step 
c       is required) :
c
              rho1 = -1. 
              do k = 1,gnum       ! For each galaxy 
                 do j = 1,5       ! for each grid 
                   rho1 = max( rho1, rhomax(k,j) )
                 end do 
              end do 
c       Factor by how much maximum density has changed :
              alpha = rhomax_ref / rho1
              rhomax_ref = rho1 
              do k = 1,gnum 
c       Upper and lower bounds on dt :
                if(halfdt(k,2).gt.fh(31,k)/2. .and.
     +           halfdt(k,2).lt.fh(30,k)/2. ) then
                   halfdt(k,2) = halfdt(k,2) * sqrt(alpha) 
c       The new time=step; also ensure it is stored in fh(4,k):
                   dt(k) = halfdt(k,1) + halfdt(k,2) 
                   fh(4,k) = dt(k)/sct
#ifdef FORT90 
c                   write(unit,'(a,es8.2,1x,es8.2,a,I6)')
#else 
c                   write(unit,'(a,e8.3,1x,e8.3,a,I6)')
#endif 
c     &             ' new times-step [m.u.,Myr] ', 
c     &               fh(4,k)*sct,fh(4,k)*sct/fh(58,1), 
c     &             ' at step ', step
                end if
              end do 
c
        end if         ! Conditional timestep adjustment : close 
c
c     Updating the positions of all particles of all galaxies :
c     =========================================================
c
c     via leap-frog integration and collecting all output data :
c     
#ifdef GNUF77   
       call CPU_TIME(t1)
#endif

         call pusher2 (step)    ! see: pusher.f and iofunc.f 
#ifdef GNUF77
      call CPU_TIME(t2)
#endif
         tp=tp+t2-t1
c
c       Update timesteps to recover time-centered scheme : 
c         
         if (ih(12).GT.0) then
           do k = 1,gnum 
              halfdt(k,1) = halfdt(k,2) 
           end do   
         end if
c
c     Looking for more output :
c
         do i = 1,gnum
            if (tfreq(i) .gt. 0) then
               if (mod(step,tfreq(i)) .eq. 0) call wsdata (step,i)
            endif
         enddo
c         
         call dostop (flag)     ! does a stop file exist ?
c         
c     Save all data for security if tsave flag is set :
c     =================================================
c
         if (tstep .gt. 1) then
            if (mod(step,tstep) .eq. 0) then
               call wdata         
               if (flag .eq. 1) goto 10
            endif
         endif
c
c     Save all data if stop file exists and stop program :
c     ====================================================
c
c     this is a pssibility to save the data of the run in case
c     of a shutdown (e.g.)
c
         if (flag .eq. 1) then
            call wdata       
            write (unit,'(a)') 
     $           'stop - file exists....   program terminated !'
            goto 10
         endif
c
      enddo                     ! end of the time-step loop
c
 10   continue
#ifdef GNUF77
      call CPU_TIME(time2)
#endif      
      time2 = time2 - time1
c
      call out_time (step,cstep,time2) ! not essential 
c
      tr = tr / real(step-cstep)
      tf = tf / real(step-cstep)
      tp = tp / real(step-cstep)
      write(unit,'(a,f20.10,a)') 'getrho:',tr,' sec/step'
      write(unit,'(a,f20.10,a)') 'getpxx:',tf,' sec/step'
      write(unit,'(a,f20.10,a)') 'pusher:',tp,' sec/step'
c

#ifdef FORT90 
90210    format( a, es8.2, 1x, a )
90211    format( /,a,es8.2, 1x, a,/ ) 
#else
90210    format( a, e8.3, 1x, a )
90211    format( /,a,e8.3,1x, a,/ ) 
#endif 
      return
c
      end
