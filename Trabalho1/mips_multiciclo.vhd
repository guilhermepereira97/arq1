-------------------------------------------------------------------------
--
-- I M P L E M E N T A � � O   P A R C I A L  D O  M I P S   (nov/2010)
--
--  ImPoRtAnTe :   VERS�O  SEM MULTIPLICA��O/DIVIS�O
--
--  Professores     Fernando Moraes / Ney Calazans
--
--  ==> The top-level processor entity is MRstd
--  21/06/2010 - Bug corrigido no mux que gera op1 - agora recebe npc e
--		n�o pc.
--  17/11/2010 (Ney) - Bugs corrigidos:
--	1 - Decodifica��o das instru��es BGEZ e BLEZ estava incompleta
--		Modificadas linhas 395 e 396 abaixo
--	2 - Defini��o de que linhas escolhem o registrador a ser escrito
--	nas instru��es de deslocamento (SSLL, SLLV, SSRA, SRAV, SSRL e SRLV)
--		Acrescentadas linhas 325 a 327 abaixo
-------------------------------------------------------------------------

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- package with basic types
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.Std_Logic_1164.all;

package p_MRstd is  
    
    -- inst_type defines the instructions decodeable by the control unit
    type inst_type is  
            ( ADDU, SUBU, AAND, OOR, XXOR, NNOR, SSLL, SLLV, SSRA, SRAV, SSRL, SRLV,
            ADDIU, ANDI, ORI, XORI, LUI, LBU, LW, SB, SW, SLT, SLTU, SLTI,
            SLTIU, BEQ, BGEZ, BLEZ, BNE, J, JAL, JALR, JR, MULTU, DIVU, MFHI, MFLO, invalid_instruction);
 
    type microinstruction is record
            CY1:   std_logic;       -- command of the first stage
            CY2:   std_logic;       --    "    of the second stage
            walu:  std_logic;       --    "    of the third stage
            wmdr:  std_logic;       --    "    of the fourth stage
            wpc:   std_logic;       -- PC write enable
            wreg:  std_logic;       -- register bank write enable
	    whilo: std_logic;	    -- write enable on HI and LO registers
            ce:    std_logic;       -- Chip enable and R_W controls
            rw:    std_logic;
            bw:    std_logic;       -- Byte-word control (mem write only)
            i:     inst_type;       -- operation specification
	    rst_md:std_logic;	    -- mult and div initialization
    end record;
         
end p_MRstd;


--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Generic register  
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.std_logic_1164.all;

entity regnbit is
           generic( INIT_VALUE : STD_LOGIC_VECTOR(31 downto 0) := (others=>'0') );
           port(  ck, rst, ce : in std_logic;
                  D : in  STD_LOGIC_VECTOR (31 downto 0);
                  Q : out STD_LOGIC_VECTOR (31 downto 0)
               );
end regnbit;

architecture regn of regnbit is 
begin

  process(ck, rst)
  begin
       if rst = '1' then
              Q <= INIT_VALUE(31 downto 0);
       elsif ck'event and ck = '0' then
           if ce = '1' then
              Q <= D; 
           end if;
       end if;
  end process;
        
end regn;

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Register Bank (R0..R31) - 31 GENERAL PURPOSE 16-bit REGISTERS
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.Std_Logic_1164.all;
use ieee.STD_LOGIC_UNSIGNED.all;   
use work.p_MRstd.all;

entity reg_bank is
       port( ck, rst, wreg :    in std_logic;
             AdRs, AdRt, adRd : in std_logic_vector( 4 downto 0);
             RD : in std_logic_vector(31 downto 0);
             R1, R2: out std_logic_vector(31 downto 0) 
           );
end reg_bank;

architecture reg_bank of reg_bank is
   type bank is array(0 to 31) of std_logic_vector(31 downto 0);
   signal reg : bank ;                            
   signal wen : std_logic_vector(31 downto 0) ;
begin            

    g1: for i in 0 to 31 generate        

        -- Remember register $0 is the constant 0, not a register.
        -- This is implemented by never enabling writes to register $0
        wen(i) <= '1' when i/=0 and adRD=i and wreg='1' else '0';
         
        -- Remember register $29, the stack pointer, points to some place
        -- near the bottom of the data memory, not the usual place 
		-- assigned by the MIPS simulator!!
        g2: if i=29 generate -- SP ---  x10010000 + x800 -- top of stack
           r29: entity work.regnbit generic map(INIT_VALUE=>x"10010800")    
                                  port map(ck=>ck, rst=>rst, ce=>wen(i), D=>RD, Q=>reg(i));
        end generate;  
                
        g3: if i/=29 generate 
           rx: entity work.regnbit port map(ck=>ck, rst=>rst, ce=>wen(i), D=>RD, Q=>reg(i));                    
        end generate;
                   
   end generate g1;   
    

    R1 <= reg(CONV_INTEGER(AdRs));    -- source1 selection 

    R2 <= reg(CONV_INTEGER(AdRt));    -- source2 selection 
   
end reg_bank;



--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- ALU - operation depends only on the current instruction 
--       (decoded in the control unit)
--
-- 22/11/2004 - subtle error correctionwas done for J!
-- Part of the work for J has been done before, by shifting IR(15 downto 0)
-- left by two bits before writing data to the IMED register 
--
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;
use work.p_MRstd.all;

entity alu is
       port( op1, op2 : in std_logic_vector(31 downto 0);
             outalu :   out std_logic_vector(31 downto 0);   
             op_alu : in inst_type   
           );
end alu;

architecture alu of alu is 
   signal menorU, menorS : std_logic ;
begin
  
    menorU <=  '1' when op1 < op2 else '0';
    menorS <=  '1' when ieee.Std_Logic_signed."<"(op1,  op2) else '0' ; -- signed
    
    outalu <=  
        op1 - op2                                when  op_alu=SUBU                     else
        op1 and op2                              when  op_alu=AAND  or op_alu=ANDI     else 
        op1 or  op2                              when  op_alu=OOR   or op_alu=ORI      else 
        op1 xor op2                              when  op_alu=XXOR  or op_alu=XORI     else 
        op1 nor op2                              when  op_alu=NNOR                     else 
        op2(15 downto 0) & x"0000"               when  op_alu=LUI                      else
        (0=>menorU, others=>'0')                 when  op_alu=SLTU  or op_alu=SLTIU    else   -- signed
        (0=>menorS, others=>'0')                 when  op_alu=SLT   or op_alu=SLTI     else   -- unsigned
        op1(31 downto 28) & op2(27 downto 0)     when  op_alu=J     or op_alu=JAL      else 
        op1                                      when  op_alu=JR    or op_alu=JALR     else 
        to_StdLogicVector(to_bitvector(op1) sll  CONV_INTEGER(op2(10 downto 6)))   when  op_alu=SSLL   else 
        to_StdLogicVector(to_bitvector(op2) sll  CONV_INTEGER(op1(5 downto 0)))    when  op_alu=SLLV   else 
        to_StdLogicVector(to_bitvector(op1) sra  CONV_INTEGER(op2(10 downto 6)))   when  op_alu=SSRA   else 
        to_StdLogicVector(to_bitvector(op2) sra  CONV_INTEGER(op1(5 downto 0)))    when  op_alu=SRAV   else 
        to_StdLogicVector(to_bitvector(op1) srl  CONV_INTEGER(op2(10 downto 6)))   when  op_alu=SSRL   else 
        to_StdLogicVector(to_bitvector(op2) srl  CONV_INTEGER(op1(5 downto 0)))    when  op_alu=SRLV   else 
        op1 + op2;    -- default for ADDU,ADDIU,LBU,LW,SW,SB,BEQ,BGEZ,BLEZ,BNE    

end alu;

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Datapath structural description
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.Std_Logic_signed.all; -- needed for comparison instructions SLTxx
use IEEE.Std_Logic_arith.all; -- needed for comparison instructions SLTxx
use work.p_MRstd.all;
   
entity datapath is
      port(  ck, rst :     in std_logic;
             i_address :   out std_logic_vector(31 downto 0);
             instruction : in std_logic_vector(31 downto 0);
             d_address :   out std_logic_vector(31 downto 0);
             data :        inout std_logic_vector(31 downto 0);  
             uins :        in microinstruction;
             IR_OUT :      out std_logic_vector(31 downto 0);
	     end_div,end_mult:	   out std_logic	     
          );
end datapath;

architecture datapath of datapath is
    signal incpc, pc, npc, IR,  result, R1, R2, RA, RB, RIN, ext16, cte_im, IMED, op1, op2, 
           outalu, RALU, MDR, mdr_int, dtpc,HI,LO,quociente,resto,D_Hi,D_Lo : std_logic_vector(31 downto 0) := (others=> '0');
    signal adD, adS : std_logic_vector(4 downto 0) := (others=> '0');    
    signal inst_branch, inst_grupo1, inst_grupoI: std_logic;   
    signal salta : std_logic := '0';
    signal produto: std_logic_vector(63 downto 0);
begin

   -- auxiliary signals 
   inst_branch  <= '1' when uins.i=BEQ or uins.i=BGEZ or uins.i=BLEZ or uins.i=BNE else 
                  '0';
                  
   inst_grupo1  <= '1' when uins.i=ADDU or uins.i=SUBU or uins.i=AAND
                         or uins.i=OOR or uins.i=XXOR or uins.i=NNOR else
                   '0';

   inst_grupoI  <= '1' when uins.i=ADDIU or uins.i=ANDI or uins.i=ORI or uins.i=XORI else
                   '0';

   --==============================================================================
   -- first_stage
   --==============================================================================
  
   incpc <= pc + 4;
  
   RNPC: entity work.regnbit port map(ck=>ck, rst=>rst, ce=>uins.CY1, D=>incpc,       Q=>npc);     
           
   RIR: entity work.regnbit  port map(ck=>ck, rst=>rst, ce=>uins.CY1, D=>instruction, Q=>IR);

   IR_OUT <= ir ;    -- IR is the datapath output signal to carry the instruction
             
   i_address <= pc;  -- connects PC output to the instruction memory address bus
   
   
   --==============================================================================
   -- second stage
   --==============================================================================
                
   -- The then clause is only used for logic shifts with shamt field       
   adS <= IR(20 downto 16) when uins.i=SSLL or uins.i=SSRA or uins.i=SSRL else 
          IR(25 downto 21);
          
   REGS: entity work.reg_bank(reg_bank) port map
        (ck=>ck, rst=>rst, wreg=>uins.wreg, AdRs=>adS, AdRt=>ir(20 downto 16), adRD=>adD,  
         Rd=>RIN, R1=>R1, R2=>R2);
    
   -- sign extension 
   ext16 <=  x"FFFF" & IR(15 downto 0) when IR(15)='1' else
             x"0000" & IR(15 downto 0);
    
   -- Immediate constant
   cte_im <= ext16(29 downto 0)  & "00"     when inst_branch='1'     else
                -- branch address adjustment for word frontier
             "0000" & IR(25 downto 0) & "00" when uins.i=J or uins.i=JAL else
                -- J/JAL are word addressed. MSB four bits are defined at the ALU, not here!
             x"0000" & IR(15 downto 0) when uins.i=ANDI or uins.i=ORI  or uins.i=XORI else
                -- logic instructions with immediate operand are zero extended
             ext16;
                -- The default case is used by addiu, lbu, lw, sbu and sw instructions
             
   -- second stage registers
   REG_S:  entity work.regnbit port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>R1,     Q=>RA);

   REG_T:  entity work.regnbit port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>R2,     Q=>RB);
  
   REG_IM: entity work.regnbit port map(ck=>ck, rst=>rst, ce=>uins.CY2, D=>cte_im, Q=>IMED);
 
 
  --==============================================================================
   -- third stage
   --==============================================================================
                      
   -- select the first ALU operand                           
   op1 <= npc  when inst_branch='1' else 
          RA; 
     
   -- select the second ALU operand
   op2 <= RB when inst_grupo1='1' or uins.i=SLTU or uins.i=SLT or uins.i=JR 
                  or uins.i=SLLV or uins.i=SRAV or uins.i=SRLV else 
          IMED; 
                 
   -- ALU instantiation
   inst_alu: entity work.alu port map (op1=>op1, op2=>op2, outalu=>outalu, op_alu=>uins.i);
                                   
   -- ALU register
   REG_alu: entity work.regnbit  port map(ck=>ck, rst=>rst, ce=>uins.walu, D=>outalu, Q=>RALU);               
 
   -- evaluation of conditions to take the branch instructions
   salta <=  '1' when ( (RA=RB  and uins.i=BEQ)  or (RA>=0  and uins.i=BGEZ) or
                        (RA<=0  and uins.i=BLEZ) or (RA/=RB and uins.i=BNE) )  else
             '0';
                  
   --multiplier and divider instantiations
   inst_mult: entity work.multiplica                   
      port map (Mcando=>R1, Mcador=>R2, clock=>ck,
      start=>uins.rst_md, endop=>end_mult, produto=>produto);
	  
   inst_div: entity work.divide                  
      generic map (32)
      port map (divisor=>R2,dividendo=>R1, clock=>ck,
	  start=>uins.rst_md, endop=>end_div, quociente=>quociente, resto=>resto);

   D_Hi <= produto(63 downto 32) when uins.i=MULTU else 
          resto; 
   D_Lo <= produto(31 downto 0) when uins.i=MULTU else 
          quociente; 

      -- HI and LO registers
   REG_HI: entity work.regnbit  port map(ck=>ck, rst=>rst, ce=>uins.whilo, 
			D=>D_Hi, Q=>HI);               
   REG_LO: entity work.regnbit  port map(ck=>ck, rst=>rst, ce=>uins.whilo, 
			D=>D_Lo, Q=>LO);   
             
   --==============================================================================
   -- fourth stage
   --==============================================================================
     
   d_address <= RALU;
    
   -- tristate to control memory write    
   data <= RB when (uins.ce='1' and uins.rw='0') else (others=>'Z');  

   -- single byte reading from memory  -- SUPONDO LITTLE ENDIAN
   mdr_int <= data when uins.i=LW  else
              x"000000" & data(7 downto 0);
       
   RMDR: entity work.regnbit  port map(ck=>ck, rst=>rst, ce=>uins.wmdr, D=>mdr_int, Q=>MDR);                 
  
   result <=    MDR when uins.i=LW  or uins.i=LBU else
		HI when uins.i=MFHI else
                LO when uins.i=MFLO else
                RALU;

   --==============================================================================
   -- fifth stage
   --==============================================================================

   -- signal to be written into the register bank
   RIN <= npc when (uins.i=JALR or uins.i=JAL) else result;
   
   -- register bank write address selection
   adD <= "11111"               when uins.i=JAL else -- JAL writes in register $31
         IR(15 downto 11)       when inst_grupo1='1' or uins.i=SLTU or uins.i=SLT
                                                     or uins.i=JALR  
						     or uins.i=MFHI or uins.i=MFLO -- added MFHI and MFLO instructions
						     or uins.i=SSLL or uins.i=SLLV
						     or uins.i=SSRA or uins.i=SRAV
						     or uins.i=SSRL or uins.i=SRLV
                                                     else
         IR(20 downto 16) -- inst_grupoI='1' or uins.i=SLTIU or uins.i=SLTI 
        ;                 -- or uins.i=LW or  uins.i=LBU  or uins.i=LUI, or default
    
   dtpc <= result when (inst_branch='1' and salta='1') or uins.i=J    or uins.i=JAL or uins.i=JALR or uins.i=JR  
           else npc;
   
   -- Code memory starting address: beware of the OFFSET! 
   -- The one below (x"00400000") serves for code generated 
   -- by the MARS simulator
   rpc: entity work.regnbit generic map(INIT_VALUE=>x"00400000")   
                            port map(ck=>ck, rst=>rst, ce=>uins.wpc, D=>dtpc, Q=>pc);

end datapath;

--------------------------------------------------------------------------
--------------------------------------------------------------------------
--  Control Unit behavioral description 
--------------------------------------------------------------------------
--------------------------------------------------------------------------
library IEEE;
use IEEE.Std_Logic_1164.all;
use work.p_MRstd.all;

entity control_unit is
        port(   ck, rst : in std_logic;          
                uins : out microinstruction;
		end_div,end_mult: in std_logic; 
                ir : in std_logic_vector(31 downto 0)
             );
end control_unit;
                   
architecture control_unit of control_unit is
   type type_state is (Sidle, Sfetch, Sreg, Salu, Swbk, Sld, Sst, Ssalta);
   signal PS, NS : type_state;
   signal i : inst_type;      
   signal uins_int: microinstruction;
begin
      
    ----------------------------------------------------------------------------------------
    -- BLOCK (1/3) - INSTRUCTION DECODING and ALU operation definition.
    -- This block generates 1 Output Function of the Control Unit
    ----------------------------------------------------------------------------------------
    i <=   ADDU   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100001" else
           SUBU   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100011" else
           AAND   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100100" else
           OOR    when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100101" else
           XXOR   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100110" else
           NNOR   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000100111" else
           SSLL   when ir(31 downto 21)="00000000000" and ir(5 downto 0)="000000" else
           SLLV   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000000100" else
           SSRA   when ir(31 downto 21)="00000000000" and ir(5 downto 0)="000011" else
           SRAV   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000000111" else
           SSRL   when ir(31 downto 21)="00000000000" and ir(5 downto 0)="000010" else
           SRLV   when ir(31 downto 26)="000000" and ir(10 downto 0)="00000000110" else
           ADDIU  when ir(31 downto 26)="001001" else
           ANDI   when ir(31 downto 26)="001100" else
           ORI    when ir(31 downto 26)="001101" else
           XORI   when ir(31 downto 26)="001110" else
           LUI    when ir(31 downto 26)="001111" else
           LW     when ir(31 downto 26)="100011" else
           LBU    when ir(31 downto 26)="100100" else
           SW     when ir(31 downto 26)="101011" else
           SB     when ir(31 downto 26)="101000" else
           SLTU   when ir(31 downto 26)="000000" and ir(5 downto 0)="101011" else
           SLT    when ir(31 downto 26)="000000" and ir(5 downto 0)="101010" else
           SLTIU  when ir(31 downto 26)="001011"                             else
           SLTI   when ir(31 downto 26)="001010"                             else
           BEQ    when ir(31 downto 26)="000100" else
           BGEZ   when ir(31 downto 26)="000001" and ir(20 downto 16)="00001" else
           BLEZ   when ir(31 downto 26)="000110" and ir(20 downto 16)="00000" else
           BNE    when ir(31 downto 26)="000101" else
           J      when ir(31 downto 26)="000010" else
           JAL    when ir(31 downto 26)="000011" else
           JALR   when ir(31 downto 26)="000000"  and ir(20 downto 16)="00000"
                                           and ir(10 downto 0) = "00000001001" else
           JR     when ir(31 downto 26)="000000" and ir(20 downto 0)="000000000000000001000" else 
           MULTU  when IR(31 downto 26)="000000" and IR(15 downto 0)="0000000000011001" else
           DIVU   when IR(31 downto 26)="000000" and IR(15 downto 0)="0000000000011011" else
	   MFHI   when IR(31 downto 16)=x"0000" and IR(10 downto 0)="00000010000" else
           MFLO   when IR(31 downto 16)=x"0000" and IR(10 downto 0)="00000010010" else
           invalid_instruction ; -- IMPORTANT: default condition is invalid instruction;
        
    assert i /= invalid_instruction
          report "******************* INVALID INSTRUCTION *************"
          severity error;
                   
    uins.i <= i;    -- this instructs the alu to execute its expected operation, if any

    ----------------------------------------------------------------------------------------
    -- BLOCK (2/3) - DATAPATH REGISTERS load control signals generation.
    ----------------------------------------------------------------------------------------
    uins.CY1   <= '1' when PS=Sfetch         else '0';
            
    uins.CY2   <= '1' when PS=Sreg           else '0';
  
    uins.walu  <= '1' when PS=Salu           else '0';
                
    uins.wmdr  <= '1' when PS=Sld            else '0';
  
    uins.wreg   <= '1' when PS=Swbk or (PS=Ssalta and (i=JAL or i=JALR)) else   '0';
   
    uins.rw    <= '0' when PS=Sst            else  '1';
                  
    uins.ce    <= '1' when PS=Sld or PS=Sst  else '0';
    
    uins.bw    <= '0' when PS=Sst and i=SB   else '1';
      
    uins.wpc   <= '1' when PS=Swbk or PS=Sst or PS=Ssalta or (PS=Salu and ((i=MULTU and end_mult='1')
			or (i=DIVU and end_div='1'))) else  '0';

    uins.whilo   <= '1' when (PS=Salu and end_mult='1' and i=MULTU)
			  or (PS=Salu and end_div='1' and i=DIVU) 
			else  '0';

    uins.rst_md   <= '1' when PS=Sreg and (i=MULTU or i=DIVU) else  '0';
    --uins <= uins_int; -- rever, pode dar merda
  
    ---------------------------------------------------------------------------------------------
    -- BLOCK (3/3) - Sequential part of the control unit - two processes implementing the
    -- Control Unit state register and the next-state (combinational) function
    --------------------------------------------------------------------------------------------- 
    process(rst, ck)
    begin
       if rst='1' then
            PS <= Sidle;          -- Sidle is the state the machine stays while processor is being reset
       elsif ck'event and ck='1' then
       
            if PS=Sidle then
                  PS <= Sfetch;
            else
                  PS <= NS;
            end if;
                
       end if;
    end process;
     
     
    process(PS, i, end_mult,end_div)
    begin
       case PS is         
      
            when Sidle=>NS <= Sidle; -- reset being active, the processor do nothing!       

            -- first stage:  read the current instruction 
            --
            when Sfetch=>NS <= Sreg;  
     
            -- second stage: read the register banck and store the mask (when i=stmsk)
            --
            when Sreg=>NS <= Salu;  
             
            -- third stage: alu operation 
            --
            when Salu =>if i=LBU  or i=LW then 
                                NS <= Sld;  
                          elsif i=SB or i=SW then 
                                NS <= Sst;
                          elsif i=J or i=JAL or i=JALR or i=JR or i=BEQ
                                    or i=BGEZ or i=BLEZ  or i=BNE then 
                                NS <= Ssalta;  
                          else if((i=MULTU and end_mult='0') or (i=DIVU and end_div='0')) then
				NS <=Salu;
 
			  else if((i=MULTU and end_mult='1') or (i=DIVU and end_div='1')) then
				NS <=Sfetch; 
			  else
                                NS <= Swbk; 
                          end if;
                         end if;
			end if;
            -- fourth stage: data memory operation  
            --
            when Sld=>  NS <= Swbk; 
            
            -- fifth clock cycle of most instructions  - GO BACK TO FETCH
            -- 
            when Sst | Ssalta | Swbk=>NS <= Sfetch;
  
       end case;

    end process;
    
end control_unit;

--------------------------------------------------------------------------
-- Top-level instantiation of the MRstd Datapath and Control Unit
--------------------------------------------------------------------------
library IEEE;
use IEEE.Std_Logic_1164.all;
use work.p_MRstd.all;

entity MRstd is
    port( clock, reset: in std_logic;
          ce, rw, bw: out std_logic;
          i_address, d_address: out std_logic_vector(31 downto 0);
          instruction: in std_logic_vector(31 downto 0);
          data: inout std_logic_vector(31 downto 0));
end MRstd;

architecture MRstd of MRstd is
      signal IR: std_logic_vector(31 downto 0);
      signal uins: microinstruction;
      signal end_mult,end_div: std_logic;
 begin

     dp: entity work.datapath   
         port map( ck=>clock, rst=>reset, IR_OUT=>IR, uins=>uins, i_address=>i_address, 
                   instruction=>instruction, d_address=>d_address,  data=>data,end_mult=>end_mult,
		   end_div=>end_div);

     ct: entity work.control_unit port map( ck=>clock, rst=>reset, IR=>IR, uins=>uins,end_mult=>end_mult,
		   end_div=>end_div);
         
     ce <= uins.ce;
     rw <= uins.rw; 
     bw <= uins.bw;
     
end MRstd;	