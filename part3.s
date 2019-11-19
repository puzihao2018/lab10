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
            LDR     R1, =0x5F5E100             // set switch time to be 10^8, which is 0.5s
            /*Load 10^8 to load register*/
            STR     R1, [R0, #0]            // load TIMER_LOAD be 10^8

            /*Load Control signal to contro register*/
            LDR     R1, [R0, #8]            // read current control register value
            ORR     R1, R1, #7              // let R1 be 0b111
            STR     R1, [R0, #8]            // load control bit (I A E) be (1 1 1)

CONFIG_JTAG://CONTRIBUTION: Zihao Pu
            LDR     R0, =JTAG_UART_BASE     // set R0 points to JTAG
            MOV     R1, #1                  // set R1 be 1, then RE is 1 and WE is 0
            STR     R1, [R0,#4]             // Write to JTAG control

IDLE:       //CONTRIBUTION: FRANCIS
            PUSH    {R0-R5,LR}
            LDR     R4, =CHAR_FLAG
			LDR     R4, [R4]
			CMP     R4, #1
			BNE     IDLE 
			LDR     R0, =CHAR_BUFFER
			B       PUT_JTAG
			LDR     R4, =CHAR_FLAG
			MOV     R5, #1
			STR     R5, [R4]
            POP     {R0-R5,PC}
            B       IDLE                    // main program simply idles

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
            LDR     R5, [R4, #ICCIAR]       // read from ICCIAR

FPGA_IRQ1_HANDLER:                         
            CMP     R5, #KEYS_IRQ           
            BNE     TIMER_HANDLER       //if not key, check timer     

            BL      KEY_ISR
            B       EXIT_IRQ

TIMER_HANDLER://CONTRIBUTION: ZIhao PU
            CMP     R5, #MPCORE_PRIV_TIMER_IRQ   
            BNE     JTAG_INTERRUPT_HANDLER        // if not timer, check JTAG

            BL      TIMER_ISR
            B       EXIT_IRQ

JTAG_INTERRUPT_HANDLER://CONTRIBUTION: FRANCIS
            CMP     R5, #JTAG_IRQ
        	BNE     UNEXPECTED
			BL      JTAG_ISR  //if equal go to JTAG ISR

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

            PUSH    {R0-R4}
            LDR     R0, =MPCORE_PRIV_TIMER
            MOV     R1, #0
            STR     R1, [R0, #0xC]          //clear interrupt register
            LDR     R2, =number
            LDR     R3, =LED_BASE           
            LDR     R4, [R2]                //read current number
            ADD     R4, R4, #1              //increment by 1
            STR     R4, [R3,#0]             // write on LED
            STR     R4, [R2,#0]             //write back to number
            POP     {R0-R4}
            BX      LR

JTAG_ISR:   //CONTRIBUTION: FRANCIS
            LDR  R0,  =JTAG_UART_BASE     //load the base address of jtag
			LDR  R1, [R0]			      //get the data in the data register 
			LSR  R1, R1, #16              //shift it right 16 bits, get only the RAVAIL value
			CMP  R1, #7                   //compair, see if greater than 7
			BLE  EXIT_IRQ                 //if not turn to exit_irq
			
			MOV  R5, #1                   //move a immediate 1 into R5
			LDR  R6, =CHAR_FLAG           //get address of charflag
			STR  R5, [R6]                 //set the flag to be one
            LDRB  R2, [R0]                //get the value in the register again
            AND  R2, R2, #0x0000000F      //get data value
			LDR  R3,  =CHAR_BUFFER        //load the char buffer address
			STR  R2, [R3]			      //store the char value into the buffer
			BX   LR

number:
    .word 0

CHAR_BUFFER:
       .word 0

CHAR_FLAG:
       .word 0
.end         