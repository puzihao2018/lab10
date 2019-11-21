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
        	BNE     TIMER_HANDLER                  // if not JTAG, go TIMER_HANDLER
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
            LDR     R2, =CURRENT_PID        //get current_pid address
            LDR     R3, [R2, #0]            //load pid
            CMP     R3, #0                  //check if pid is 0
            BEQ     pro0                    //if 0, go pro0
            B       pro1                    //if 1, go pro1

pro0:       //CONTRIBUTION Yuqi, Fu
            LDR     R7, =PD_ARRAY          //get the pd_array address
            MOV     R3, #1
            STR     R3, [R2]                  //update current_pid to be 1
            
            /***store normal registers outside interrupt***/
            STR     R8, [R7, #32]
            STR     R9, [R7, #36]
            STR     R10,[R7, #40]
            STR     R11,[R7, #44]
            STR     R12,[R7, #48]

            /***store spsr***/
            MRS     R0, SPSR
            STR     R0, [R7, #0x40]

            /***clear interrupt***/
            LDR     R5, =29
            STR     R5, [R4, #ICCEOIR]      // write to ICCEOIR

            /***store registers before interrupt***/
            LDR     R8, =PD_ARRAY           // already backed-up, use to store pd-array address
            POP     {R0-R7,LR}              // restore the stored R0-R7 and LR before interrupting
            STR     R0, [R8, #0]
            STR     R1, [R8, #4]
            STR     R2, [R8, #8]
            STR     R3, [R8, #12]
            STR     R4, [R8, #16]
            STR     R5, [R8, #20]
            STR     R6, [R8, #24]
            STR     R7, [R8, #28]
            STR     LR, [R8, #0x3C]
            /***end store normal registers***/

            /***FORCE GOES TO SVR, AND SAVE LR/PC***/
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            STR     SP, [R8, #52]          // store SVC sp to pd_array
            STR     LR, [R8, #56]          // store SVC lr tp pd_array
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            /***Done with storing***/

            /***Starting Loading Normal Registers***/
            LDR     R8, =PD_ARRAY           // copy pd_array address to R8
            LDR     R9, =PD_OFFSET          // copy pd_offset address to R9
            LDR     R10, [R9]               // load pd offset to r10
            ADD     R8, R8, R10             // PD_array base address of process 1
            LDR     R0, [R8,#0]
            LDR     R1, [R8,#4]
            LDR     R2, [R8,#8]
            LDR     R3, [R8,#12]
            LDR     R4, [R8, #16]
            LDR     R5, [R8, #20]
            LDR     R6, [R8, #24]
            LDR     R7, [R8, #28]
            PUSH    {R0-R7}                 //R0-R7 will be used later
            
            /***Loading SPSR***/
            LDR     R0, [R8, #0x40]         //Load PROC1 SPSR to R0
            MSR     SPSR, R0                //Copies R0 into SPSR

            /***Load other normal registers***/
            MOV     R7, R8                  //mov, let R7 be PD_array base address of process 1
            LDR     R8, [R7, #32]
            LDR     R9, [R7, #36]
            LDR     R10,[R7, #40]
            LDR     R11,[R7, #44]
            LDR     R12,[R7, #48]
            /***Normal registers restored finished***/
            
            /***FORCE GOES TO SVR, AND Restore LR&PC***/
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            LDR     SP, [R7, #52]          // Restore SVC sp from pd_array
            LDR     LR, [R7, #56]          // Restore SVC lr from pd_array
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            /***Done with Restoring***/

            /***SWTICH PROCESS***/
            POP     {R0-R7}                 //POP back used R0-R7
            SUBS    PC, LR, #4              

pro1:       //CONTRIBUTION Yuqi, Fu
            LDR     R7, =PD_ARRAY          //get the pd_array address
            ADD     R7, R7, #0x48          //get the pd_array base address of process1
            MOV     R3, #0
            STR     R3, [R2]                  //update current_pid to be 1
            
            /***store normal registers outside interrupt***/
            STR     R8, [R7, #32]
            STR     R9, [R7, #36]
            STR     R10,[R7, #40]
            STR     R11,[R7, #44]
            STR     R12,[R7, #48]

            /***store spsr***/
            MRS     R0,SPSR
            STR     R0, [R7, #0x40]
            
            /***clear interrupt***/
            LDR     R5, =29
            STR     R5, [R4, #ICCEOIR]      // write to ICCEOIR

            /***store registers before interrupt***/
            MOV     R8, R7                  // already backed-up, use to store pd-array base address of process2
            POP     {R0-R7,LR}              // restore the stored R0-R7 and LR before interrupting
            STR     R0, [R8, #0]
            STR     R1, [R8, #4]
            STR     R2, [R8, #8]
            STR     R3, [R8, #12]
            STR     R4, [R8, #16]
            STR     R5, [R8, #20]
            STR     R6, [R8, #24]
            STR     R7, [R8, #28]
            STR     LR, [R8, #0x3C]
            /***end store normal registers***/

            /***FORCE GOES TO SVR, AND SAVE LR/PC***/
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            STR     SP, [R8, #52]          // store SVC sp to pd_array
            STR     LR, [R8, #56]          // store SVC lr tp pd_array
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            /***Done with storing***/

            /***Starting Loading Normal Registers***/
            LDR     R8, =PD_ARRAY           // copy pd_array base address to R8
            LDR     R0, [R8,#0]
            LDR     R1, [R8,#4]
            LDR     R2, [R8,#8]
            LDR     R3, [R8,#12]
            LDR     R4, [R8, #16]
            LDR     R5, [R8, #20]
            LDR     R6, [R8, #24]
            LDR     R7, [R8, #28]
            PUSH    {R0-R7}                 //R0-R7 will be used later
            
            /***Loading SPSR***/
            LDR     R0, [R8, #0x40]         //Load PROC1 SPSR to R0
            MSR     SPSR, R0                //Copies R0 into SPSR            MOV     R7, R8                  //mov, let R7 be PD_array base address of process 1
            
            /***Load other normal registers***/
            LDR     R8, [R7, #32]
            LDR     R9, [R7, #36]
            LDR     R10,[R7, #40]
            LDR     R11,[R7, #44]
            LDR     R12,[R7, #48]
            /***Normal registers restored finished***/
            
            /***FORCE GOES TO SVR, AND Restore LR&PC***/
            MOV     R1, #0b11010011         // interrupts masked, MODE = SVC
            MSR     CPSR, R1                // change to supervisor mode
            LDR     SP, [R7, #52]          // Restore SVC sp from pd_array
            LDR     LR, [R7, #56]          // Restore SVC lr from pd_array
            MOV     R1, #0b11010010         // interrupts masked, MODE = IRQ
            MSR     CPSR_c, R1              // change to IRQ mode
            /***Done with Restoring***/

            /***SWTICH PROCESS***/
            POP     {R0-R7}                 //POP back used R0-R7
            SUBS    PC, LR, #4            


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

PD_OFFSET:      .word 68 

.end