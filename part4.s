.include    "address_map_arm.s" 
.include    "interrupt_ID.s" 

/* ********************************************************************************
 * This program demonstrates use of interrupts with assembly language code.
 * The program responds to interrupts from the pushbutton KEY port in the FPGA.
 *
 * The interrupt service routine for the pushbutton KEYs indicates which KEY has
 * been pressed on the LED display.
 ********************************************************************************/

.section    .vectors, "ax" 

            B       _start                  // reset vector
            B       SERVICE_UND             // undefined instruction vector
            B       SERVICE_SVC             // software interrrupt vector
            B       SERVICE_ABT_INST        // aborted prefetch vector
            B       SERVICE_ABT_DATA        // aborted data vector
.word       0 // unused vector
            B       SERVICE_IRQ             // IRQ interrupt vector
            B       SERVICE_FIQ             // FIQ interrupt vector

.text        
.global     _start 
_start:                                     
/* Set up stack pointers for IRQ and SVC processor modes */
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            LDR     SP, =A9_ONCHIP_END - 3  // set IRQ stack to top of A9 onchip memory
/* Change to SVC (supervisor) mode with interrupts disabled */
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            LDR     SP, =DDR_END - 3        // set SVC stack to top of DDR3 memory

            BL      CONFIG_GIC              // configure the ARM generic interrupt controller

                                            // write to the pushbutton KEY interrupt mask register
            LDR     R0, =KEY_BASE           // pushbutton KEY base address
            MOV     R1, #0xF               // set interrupt mask bits
            STR     R1, [R0, #0x8]          // interrupt mask register is (base + 8)

                                            // enable IRQ interrupts in the processor
            MOV     R0, #0b01010011         // IRQ unmasked, MODE = SVC
            MSR     CPSR_c, R0              

CONFIG_TIMER://CONTRIBUTION: FRANCIS
            LDR     R0, =MPCORE_PRIV_TIMER  // set R0 points to MPCORE_PRIV_TIMER
            LDR     R1, =500                // set timer interrupt to be 500, so switch threads every 0.00025s
            /*Load 10^8 to load register*/
            STR     R1, [R0, #0]            // load TIMER_LOAD be 10^8

            /*Load Control signal to contro register*/
            MOV     R1, #7
            STR     R1, [R0, #8]            // load control bit (I A E) be (1 1 1)

CONFIG_JTAG://CONTRIBUTION: Zihao Pu
            LDR     R0, =JTAG_UART_BASE     // set R0 points to JTAG
            MOV     R1, #0x1
            STR     R1, [R0,#0x4]             // Write to JTAG control

CONTFIG_PID://CONTRIBUTION:Zihao Pu
            LDR     R0, =CURRENT_PID        //set R0 points to CURRENT_PID
            MOV     R1, #0                  //PID should be 0 at first
            STR     R1, [R0]                //write 0 to CURRENT_PID

IDLE:       //CONTRIBUTION: FRANCIS
            LDR     R1, =CHAR_FLAG
			LDR     R0, [R1]
			CMP     R0, #1
			BNE     IDLE 
			LDR     R2, =CHAR_BUFFER
            LDRB    R0, [R2,#0]
			BL      PUT_JTAG
            LDR     R1, =CHAR_FLAG
			MOV     R2, #0
			STR     R2, [R1]
            B       IDLE                    // main program simply idles

PROC1:      //CONTRIBUTION: FRANCIS
            MOV R0, #0
			LDR R1, =0xFF200000
loop:       ADD R0,R0,#1
            STR R0,[R1] 			
			MOV R2, #0
doloop:	    ADD R2,R2,#1
			CMP R2, #256 //my chosen large number
			BLT doloop
			B   loop

PUT_JTAG:   
            LDR R1, =0xFF201000 // JTAG UART base address
            LDR R2, [R1, #4] // read the JTAG UART control register
            LDR R3, =0xFFFF
            ANDS R2, R2, R3 // check for write space
            BEQ END_PUT // if no space, ignore the character
            STR R0, [R1] // send the character
END_PUT:    BX LR

/* Define the exception service routines */

/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:                                
            B       SERVICE_UND             

/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:                                
            B       SERVICE_SVC             

/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:                           
            B       SERVICE_ABT_DATA        

/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:                           
            B       SERVICE_ABT_INST        

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:                                
            PUSH    {R0-R7, LR}             

/* Read the ICCIAR from the CPU interface */
            LDR     R4, =MPCORE_GIC_CPUIF   
            LDR     R5, [R4, #ICCIAR]            // read from ICCIAR

FPGA_IRQ1_HANDLER:                         
            CMP     R5, #KEYS_IRQ           
            BNE     JTAG_INTERRUPT_HANDLER       // if not key, check JTAG     
            BL      KEY_ISR                      // if equal go to KEY ISR    
            B       EXIT_IRQ

JTAG_INTERRUPT_HANDLER://CONTRIBUTION: FRANCIS
            CMP     R5, #JTAG_IRQ
        	BNE     UNEXPECTED                  // if not JTAG, go TIMER_HANDLER
			BL      JTAG_ISR                    // if equal go to JTAG ISR
            B       EXIT_IRQ


TIMER_HANDLER://CONTRIBUTION: ZIhao PU
            CMP     R5, #MPCORE_PRIV_TIMER_IRQ   
            BNE     UNEXPECTED                  // if not recognized, go unexpected
            BL      TIMER_ISR                   // if equal, exit IRQ
            B       EXIT_IRQ                    

UNEXPECTED:
            B       UNEXPECTED      //if not recognized, stop here

EXIT_IRQ:                                   
/* Write to the End of Interrupt Register (ICCEOIR) */
            STR     R5, [R4, #ICCEOIR]      // write to ICCEOIR

            POP     {R0-R7, LR}             
            SUBS    PC, LR, #4              

/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:                                
            B       SERVICE_FIQ             

/*TIMER_ISR*/   //CONTRIBUTION: Zihao PU
TIMER_ISR:

            LDR     R0, =MPCORE_PRIV_TIMER
            MOV     R1, #0
            STR     R1, [R0, #0xC]          //clear interrupt register
            LDR     R2, =CURRENT_PID        //read current_pid
            LDR     R2, [R2, #0]
            CMP     R2, #0                  //check if pid is 1
            BEQ     pro0                    //if 0, go pro0
            B       pro1                    //if 1, go pro1
/*
            MOVEQ   R3, #1                  //if 1, write 0
            MOVNE   R3, #0                  //if 0, write 1
            STR     R3, [R2, #0]            //writing new pid to CURRENT_PID
            BX      LR
*/
pro0:      //CONTRIBUTION: Fuyu Qi
            LDR   R12,=PD_ARRAY          //get the array address
            STR   R0, [R12, #0]          //store register 0-5 for use
			STR   R1, [R12, #4]          
			STR   R2, [R12, #8]
			STR   R3, [R12, #12]
			STR   R4, [R12, #16]
			STR   R5, [R12, #20]
			STR   R14, [R12, #60]        //store pc (r14 in irq mode )
			MSR   R0, spsr
			STR   R0, [R12, #64]         //store cpsr (saved in spsr)
			MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
			STR  R13, [R12, #52]           //store r13 and r14 (lr and sp)
			STR  R14, [R12, #56]
			
			LDR   R7, =CURRENT_PID          //change current value to its opposite on current_pid
			LDR   R8, [R7]
			MVN   R8, R8
			STR   R8, [R7]
			
			MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR, R1                // change to IRQ mode
			LDR  R12, =PD_ARRAY+PD_OFFSET   //read address of the other half of the array
			LDR   R0, [R12, #0]             //load it back
			LDR   R1, [R12, #4]            
			LDR   R2, [R12, #8]
			LDR   R3, [R12, #12]
			LDR   R4, [R12, #16]
			LDR   R5, [R12, #20]
			LDR  R13, [R12, #52]            //load back r13 and r14
			LDR  R14, [R12, #56]
			SUBS PC, LR, #4                  //recover program counter and cpsr

			
			B    getout
			
			
pro1:		LDR   R12,=PD_ARRAY+PD_OFFSET
            STR   R0, [R12, #0]
			STR   R1, [R12, #4]
			STR   R2, [R12, #8]
			STR   R3, [R12, #12]
			STR   R4, [R12, #16]
			STR   R5, [R12, #20]
			STR   R14, [R12, #60]
			MSR   R0, spsr
			STR   R0, [R12, #64]
			MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
			STR  R13, [R12, #52]
			STR  R14, [R12, #56]
			
			LDR   R7, =CURRENT_PID
			LDR   R8, [R7]
			MVN   R8, R8
			STR   R8, [R7]
			
			MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR, R1                // change to IRQ mode
			LDR  R12, =PD_ARRAY
			LDR   R0, [R12, #0]
			LDR   R1, [R12, #4]
			LDR   R2, [R12, #8]
			LDR   R3, [R12, #12]
			LDR   R4, [R12, #16]
			LDR   R5, [R12, #20]
			LDR  R13, [R12, #52]
			LDR  R14, [R12, #56]
			SUBS PC, LR, #4
getout:			BX      LR                    //return to the original program 

JTAG_ISR:   //CONTRIBUTION: FRANCIS

            LDR  R0,  =JTAG_UART_BASE       // load the base address of jtag
            LDR  R1,  =CHAR_FLAG            // load the base address of char_flag
            LDR  R2,  =CHAR_BUFFER          // load the base address of 
            MOV  R3,  #1
            LDRB R6, [R0]
            STR  R3, [R1]
            STR  R6, [R2]

            BX   LR

CHAR_BUFFER:
                .word 0

CHAR_FLAG:
                .word 0

CURRENT_PID:    .word 0

PD_ARRAY:       .fill 17,4,0xDEADBEEF
                .fill 13,4,0xDEADBEE1
                .word 0x3F000000 // SP
                .word 0 // LR
                .word PROC1+4 // PC
                .word 0x53 // CPSR (0x53 means IRQ enabled, mode = SVC)

PD_OFFSET:.word 68 

.end         