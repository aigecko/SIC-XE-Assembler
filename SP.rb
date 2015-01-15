#coding: utf-8
initMnemonicList=->(){
    MnemonicList={
        ADD:     0x18,        ADDF:    0x58,        ADDR:     0x90,        AND:     0x40,
        CLEAR:   0xB4,        COMP:    0x28,        COMPF:    0x88,        COMPR:   0xA0,
        DIV:     0x24,        DIVF:    0x64,        DIVR:     0x9C,        FIX:     0xC4,
        FLOAT:   0xC0,        HIO:     0xF4,        J:        0x3C,        JEQ:     0x30,
        JGT:     0x34,        JLT:     0x38,        JSUB:     0x48,        LDA:     0x00,
        LDB:     0x68,        LDCH:    0x50,        LDF:      0x70,        LDL:     0x08,
        LDT:     0x74,        LDX:     0x04,        LPS:      0xD0,        MULF:    0x60,
        MULR:    0x98,        NORM:    0xC8,        OR:       0x44,        RD:      0xD8,
        RMO:     0xAC,        RSUB:    0x4C,        SHIFTL:   0xA4,        SHIFTR:  0xA8,
        SIO:     0xF0,        SSK:     0xEC,        STA:      0x0C,        STB:     0x78,
        STCH:    0x54,        STF:     0x80,        STI:      0xD4,        STL:     0x14,
        STS:     0x7C,        STSW:    0xE8,        STT:      0x84,        STX:     0x10,
        SUB:     0x1C,        SUBF:    0x5C,        SUBR:     0x94,        SVC:     0xB0,
        TD:      0xE0,        TIO:     0xF8,        TIX:      0x2C,        TIXR:    0xB8,
        WD:      0xDC,        LDS:     0x6C,        MUL:      0x20
    }
}
initDirectives=->(){
    Directives=[
        :START,:END,:BYTE,:WORD,:RESB,:RESW,
		:BASE,:NOBASE,
		:EQU,:LTORG,:ORG,
		:USE,:CSECT,:EXTREF,:EXTDEF
    ]
}
initRegExps=->(){
    RegExps={
        :Line=> /(\d*)\s*(.*)/, #get string after line and spaces
        :Comment=> /^\d*\s*\..*/,    #detect whether comment
        :Header=> /^\s*(\d*)\s*(\w*)\s*START\s*(\d*)\s*.*/, #get header strings
        :End=> /^\s*(\d*)\s*END\s+(\w*)?\s*.*/, #detect last line
        :FirstToken=> /\d*\t*(\+?)([\w]*)\s*(.*)/, #get the first word
        :Argument=> /,?([@#='\w]*)\s*(.*)/, #get a argument
        :XRegUsed=> /\s*,\s*X\s*(.*)/, #detect "X" and get comment
        :LastPart=> /\s*(.*)/, #get last part comment
        :Indirect=> /(@[\w_]*)/, #detect and get whether indirect addressing
        :Immediate=> /#[\w_]*/, #detect and get whether immediate addressing
        :LiteralString=> /=C'(\w*)'/, #get string part of a literal
        :LiteralHex=> /=X'[A-Fa-f0-9]*'/, #get hex digit part of a literal
		:CharString=> /[C|c]'(?<string>\w*)'/, #get character string part
		:HexString=> /[X|x]'(?<string>[\dA-Fa-f]*)'/ #get hex-digit string part
    }
	list=(MnemonicList.keys+Directives).sort_by{|s| -s.length}.join('|')
	RegExps[:Middle]=Regexp.new(
		'^(\s*(?<Line>\d*))?'+ #line number part
		'\s*((?<Label>\w+)\s+)?'+ #label part
		'(?<Operator>\+?'+ #operator
		"(#{list}))"+ #operator part
		'\s+((?<Operand>(\S+(\s*,\s*\S+)?)))?'+ #operand part
		'.*$', #comment part
		Regexp::IGNORECASE)
}
initArgNumTable=->(){
    #most opcodes have 1 argument
    ArgNum=Hash.new(1)
    #some have no argument
    [:FIX,:FLOAT,:HIO,:NORM,:RSUB,:SIO,:TIO].each do |op|
        ArgNum[op]=0
    end
    #some have 2 arguments
    [:ADDR,:COMPR,:DIVR,:MULR,:RMO,:SHIFTL,:SHIFTR,:SUBR].each do |op|
        ArgNum[op]=2
    end
}
initFormatTable=->(){
    #format4 is decided dynamically
    #most opcodes use format3
    FormatTable=Hash.new(3)
    #some use format1
    [:FIX,:FLOAT,:HIO,:NORM,:SIO,:TIO].each do |op|
        FormatTable[op]=1
    end
    #some use format2
    [:ADDR,:CLEAR,:COMPR,:DIVR,:MULR,:RMO,
     :SHIFTL,:SHIFTR,:SUBR,:SVC,:TIXR].each do |op|
        FormatTable[op]=2
    end
}
initRegisterTable=->(){
    RegTable={
        A: 0,X: 1,L: 2,B: 3,S: 4,
        T: 5,F: 6,     PC:8,SW:9,
    }
}
initLineConvTable=->(){
    Line={}
}
initOffsetTable=->(){
	OffsetTable={
		N:17,I:16,X:15,B:14,P:13,E:12
	}
}

Sections={}
currentName=nil
currentSection=nil

CreateSection=->(pack){
	return {
		StartLoc: pack[:StartAddress],
		LocCtr: pack[:StartAddress],
		BaseCtr: nil,

		HeaderRecord: String.new(),
		TextRecord: String.new(),
		TextArray: Hash.new(),
		EndRecord: String.new(),
		ModRecord: String.new(),

		SymbolTable: Hash.new(),
		AddressingQueue: Hash.new()
	}
}

initProcs=->(){
	WarningAction=->(fileLineCount,wrnno){
		STDERR.print("Warning: ")
		STDERR.puts(
		case wrnno
		when -1
			"Program Name was set to 'NONAME' because of no specified name"
		end
		)
		STDERR.puts("At line #{Line[fileLineCount]||fileLineCount}")
	}
    ErrorAction=->(fileLineCount,errno){
        STDERR.puts(
        case errno
        when -1
            "Not a Mnemonic or Directive after LABLE"
        when -2
            "Improper Header Format"
        when -3
            "Over 6 character of Program's Name"
        when -4
            "Define a Mnemonic or Directive as a Label is illegal"
        when -5
            "Unknown StartPoint after 'END'"
		when -6
			"Multiple definition of Label"
		when -7
			"Operator not found"
		when -8
			"Format1/2 can't use '+'"
		when -9
			"Unknown string format behind 'BYTE'"
        else
            "Runtime Error"
        end
        )		
        STDERR.puts(
		if(Line[fileLineCount]&&Line[fileLineCount]!="")
			"At line code-mode: #{Line[fileLineCount]}"
		else
			"At line text-mode: #{fileLineCount}"
		end
		)
        exit(errno)
    }
    ExitAction=->(){ exit(0) }
    FinalOutput=->(pack){
		for sym,val in currentSection[:SymbolTable].sort_by{|s,v| v}
			STDERR.puts "%s: 0x%04X"%[sym,val]
		end
		
		for name,section in Sections
			puts section[:HeaderRecord]			
			for loc,code in section[:TextArray]
				print 'T'
				print "%06X%02X"%[loc,code.to_s.size/2]
				if(code.class==String)
					puts code
				else
					puts "%X"%code
				end
			end
			print section[:ModRecord]
			puts section[:EndRecord]
		end
		ExitAction.call
    }

	ProcDefineSymbol=->(){}
	ProcProgramBlock=->(pack){

	}
	ProcContralSection=->(){}

	SetLastLine=->(pack){
		currentSection[:HeaderRecord]<< "%06X" % (
			currentSection[:LocCtr]-currentSection[:StartLoc])

		currentSection[:EndRecord]<< 'E'
		currentSection[:EndRecord]<< "%06X"%currentSection[:StartLoc]
    }
	GetLastLine=->(pack){
        if pack[:StartPoint]
            pack[:StartPoint]=currentSection[:SymbolTable][pack[:StartPoint]]
            if(!pack[:StartPoint])
                ErrorAction.call(pack[:Line],-5)
            end
        end
    }
	ProcLastLine=->(pack){
		GetLastLine.call(pack)
		SetLastLine.call(pack)
		return FinalOutput.call(pack)
	}
	ProcMnemonicChangeFormat=->(pack){
		#detect format4
		if(pack[:Operator][0]=='+')
			#find mnemonic
			if(FormatTable[pack[:Operator][1..-1].to_sym]<=2)
				ErrorAction.call(pack[:Line],-8)
			end
			pack[:Format]=4
		else
			pack[:Format]=FormatTable[pack[:Operator].to_sym]
		end
		#change to inter format
		if(pack[:Format]==4)
			pack[:Operator]=pack[:Operator][1..-1].to_sym
		else
			pack[:Operator]=pack[:Operator].to_sym
		end
	}
	ProcMergeSymbol=->(pack){
		target=pack[:Operand]
		symbolTable=currentSection[:SymbolTable]
		textArray=currentSection[:TextArray]
		locCtr=currentSection[:LocCtr]
		if(target=~/\d+/)
			target=target.to_i
		end
		if(!symbolTable.keys.include?(target)&&target.class!=Fixnum)
			#forward reference first appear
			symbolTable[target]=[]
			symbolTable[target]<<[locCtr,pack]
		elsif(symbolTable[target].class!=Fixnum&&target.class!=Fixnum)
			#forward reference
			symbolTable[target]<<[locCtr,pack]
		else
			#backward reference
			if(pack[:Format]==4)
				#Format 4 use immediate addressing
				textArray[locCtr]>>=8				
				#immediate tag
				textArray[locCtr]|=1<<OffsetTable[:I]
				#extend tag
				textArray[locCtr]|=1<<OffsetTable[:E]
				if(pack[:Mode]!=:IMMEDIATE)
					textArray[locCtr]|=1<<OffsetTable[:N]
				end
				textArray[locCtr]<<=8
				if(target.class==Fixnum)
					textArray[locCtr]|=target
				else
					textArray[locCtr]|=currentSection[:SymbolTable[target]]
					currentSection[:ModRecord]<<("M%06X05\n"%(locCtr+1))
				end
			else
				#x register tag
				if(pack[:XRegUsed])
					textArray[locCtr]|=1<<OffsetTable[:X]
				end
				case pack[:Mode]
				when :IMMEDIATE
					textArray[locCtr]|=1<<OffsetTable[:I]
					if(target.class==Fixnum)
						textArray[locCtr]|=target
					else
						textArray[locCtr]|=symbolTable[target]
					end
				when :INDIRECT
					textArray[locCtr]|=1<<OffsetTable[:N]
					if(target.class==Fixnum)
						textArray[locCtr]|=target
					else
						textArray[locCtr]|=symbolTable[target]
					end
				else
					#detect PC relative				
					offset=symbolTable[target]-currentSection[:LocCtr]
					textArray[locCtr]|=1<<OffsetTable[:I]
					textArray[locCtr]|=1<<OffsetTable[:N]
					if(offset>=0&&offset<=2050)
						textArray[locCtr]|=offset-3						
						textArray[locCtr]|=1<<OffsetTable[:P]
					elsif(offset<0&&offset>=-2048)
						textArray[locCtr]|=4096+offset-3
						textArray[locCtr]|=1<<OffsetTable[:P]						
					elsif(offset<4095)
						if(currentSection[:BaseCtr]&&
							symbolTable[currentSection[:BaseCtr]].class==Fixnum&&
							symbolTable[target].class==Fixnum)
							#B relative
							textArray[locCtr]|=1<<OffsetTable[:B]
							textArray[locCtr]|=symbolTable[target]-symbolTable[currentSection[:BaseCtr]]
						else
							#B forward reference
						end
					end					
				end				
			end
			currentSection[:TextArray][currentSection[:LocCtr]]=
				"%0#{pack[:Format]*2}X"%currentSection[:TextArray][currentSection[:LocCtr]]
			#TODO
		end
	}
	ProcMnemonicNormalCase=->(pack){
		currentSection[:TextArray][currentSection[:LocCtr]]=
			MnemonicList[pack[:Operator]]<<((pack[:Format]-1)*8)					
		target=pack[:Operand][0]
		pack[:Mode]=(
		case target[0]
		when '@'
			target=target[1..-1]
			:INDIRECT
		when '#' 
			target=target[1..-1]
			:IMMEDIATE
		when '=' 
			target=target[1..-1]
			:LITERRAL
		else :NORMAL
		end)
		pack[:Operand]=target
		ProcMergeSymbol.call(pack)
	}
    ProcMnemonic=->(pack){
		ProcMnemonicChangeFormat.call(pack)
		#generate binary code
		if(ArgNum[pack[:Operator]]==0)
			currentSection[:TextArray][currentSection[:LocCtr]]=
				MnemonicList[pack[:Operator]]<<((pack[:Format]-1)*8)
			#no operand , direct output binary
			if(pack[:Operator]==:RSUB)
				currentSection[:TextArray][currentSection[:LocCtr]]|=1<<OffsetTable[:N]
				currentSection[:TextArray][currentSection[:LocCtr]]|=1<<OffsetTable[:I]
			end
			currentSection[:TextArray][currentSection[:LocCtr]]=
				"%0#{pack[:Format]*2}X"%currentSection[:TextArray][currentSection[:LocCtr]]
		elsif(ArgNum[pack[:Operator]]==2)
			#with 2 register operands
			currentSection[:TextArray][currentSection[:LocCtr]]=
				MnemonicList[pack[:Operator]]<<((pack[:Format]-1)*8)
			#whether the 2nd operand is a number
			currentSection[:TextArray][currentSection[:LocCtr]]+=
			if(pack[:Operator]==:SHIFTL||
			   pack[:Operator]==:SHIFTR)
				pack[:Operand][1].to_i-1
			else
				RegTable[pack[:Operand][1].to_sym]
			end
			currentSection[:TextArray][currentSection[:LocCtr]]+=
				RegTable[pack[:Operand][0].to_sym]<<4
			currentSection[:TextArray][currentSection[:LocCtr]]=
				"%0#{pack[:Format]*2}X"%currentSection[:TextArray][currentSection[:LocCtr]]
		else
			#normal case with 1 operand
			#detect special type operator
			if(pack[:Format]==2)
				currentSection[:TextArray][currentSection[:LocCtr]]=
					MnemonicList[pack[:Operator]]<<8
				currentSection[:TextArray][currentSection[:LocCtr]]+=
				case pack[:Operator]
				when :CLEAR,:TIXR
					RegTable[pack[:Operand][0].to_sym]<<4
				when :SVC
					pack[:Operand][0].to_i
				end
			else
				ProcMnemonicNormalCase.call(pack)
			end
		end
		currentSection[:LocCtr]+=pack[:Format]
		return ProcMiddle
	}
	ProcDirective=->(pack){
		length=
		case pack[:Operator].to_sym
		when :RESB then pack[:Operand][0].to_i
		when :RESW then pack[:Operand][0].to_i*3
		when :WORD then 3
		when :BYTE
			case pack[:Operand][0]
			#start with 'C' or 'c'
			when RegExps[:CharString]
				pack[:String]=$1
				currentSection[:TextArray][currentSection[:LocCtr]]=0
				#change ASCII to binary code
				for char in pack[:String].chars
					currentSection[:TextArray][currentSection[:LocCtr]]<<=8
					currentSection[:TextArray][currentSection[:LocCtr]]+=
					char.ord
				end
				pack[:String].size
			#star with 'X' or 'x'
			when RegExps[:HexString]
				pack[:String]=$1
				if(pack[:String].size%2==1)
					pack[:String]='0'+pack[:String]
				end
				#2 digit to 1 byte				
				currentSection[:TextArray][currentSection[:LocCtr]]=pack[:String]
				pack[:String].size/2
			else
				ErrorAction.call(pack[:Line],-9)
			end
		when :BASE
			#set BASE counter
			currentSection[:BaseCtr]=pack[:Operand][0] and 0
		when :NOBASE
			#clear BASE counter
			currentSection[:BaseCtr]=nil or 0
		else 0
		end
		currentSection[:LocCtr]+=length
		return ProcMiddle
	}

	SetMidLine=->(pack){
        textRecord<< 'T'
        return GetMidLine
    }
    ProcMiddle=->(pack){
		line=STDIN.gets
        #if END appeared
        if(line=~RegExps[:End])
            #set line number
            ($1=="") or Line[pack[:Line]]=$1
            #set start point
            pack[:StartPoint]=$2
            return ProcLastLine.call(pack)
        end
		#ignore comment
		if(line=~RegExps[:Comment])
			return ProcMiddle
		end

		#normal operator
		if(result=line.match(RegExps[:Middle]))
			#set line number
			Line[pack[:Line]]=result[:Line]
			pack[:Label]=result[:Label]
			#if label appear twice
			if(currentSection[:SymbolTable].keys.include? pack[:Label]&&
			   currentSection[:SymbolTable][pack[:Label]].class!=Fixnum)
				ErrorAction.call(pack[:Line],-6)
			end
			if(pack[:Label])
				if(table=currentSection[:SymbolTable][pack[:Label]])					
					currentSection[:SymbolTable][pack[:Label]]=currentSection[:LocCtr]
					symbolTable=currentSection[:SymbolTable]
					textArray=currentSection[:TextArray]
					for location,data in table
						xRegUsed=data[:XRegUsed]
						target=data[:Operand]
						#backward reference
						if(data[:Format]==4)
							#Format 4 use immediate addressing
							textArray[location]>>=8	
							#immediate tag
							textArray[location]|=1<<OffsetTable[:I]
							#extend tag
							textArray[location]|=1<<OffsetTable[:E]
							if(data[:Mode]!=:IMMEDIATE)
								textArray[location]|=1<<OffsetTable[:N]
							end
							textArray[location]<<=8
							if(target.class==Fixnum)
								textArray[location]|=target
							else
								textArray[location]|=currentSection[:SymbolTable][target]
								currentSection[:ModRecord]<<("M%06X05\n"%(location+1))
							end
						else
							#x register tag
							if(data[:XRegUsed])
								textArray[location]|=1<<OffsetTable[:X]
							end
							case data[:Mode]
							when :IMMEDIATE
								textArray[location]|=1<<OffsetTable[:I]
								if(target.class==Fixnum)
									textArray[location]|=target
								else
									textArray[location]|=symbolTable[target]
								end
							when :INDIRECT
								textArray[location]|=1<<OffsetTable[:N]
								if(target.class==Fixnum)
									textArray[location]|=target
								else
									textArray[location]|=symbolTable[target]
								end
							else
								#detect PC relative
								offset=symbolTable[target]-location
								textArray[location]|=1<<OffsetTable[:I]
								textArray[location]|=1<<OffsetTable[:N]
								if(offset>=0&&offset<=2050)
									textArray[location]|=offset-3
									textArray[location]|=1<<OffsetTable[:P]
								elsif(offset<0&&offset>=-2048)
									textArray[location]|=4096+offset-3
									textArray[location]|=1<<OffsetTable[:P]
								elsif(offset<4095)
									if(currentSection[:BaseCtr]&&
									   symbolTable[currentSection[:BaseCtr]].class==Fixnum&&
									   symbolTable[target].class==Fixnum)
										#B relative
										textArray[location]|=1<<OffsetTable[:B]
										textArray[location]|=symbolTable[target]-symbolTable[currentSection[:BaseCtr]]
									else								
										#B forward reference
									end
								end
							end							
						end
						if(data[:Format]==4)
							currentSection[:TextArray][location]<<8
						end
						currentSection[:TextArray][location]=
							"%0#{data[:Format]*2}X"%currentSection[:TextArray][location]
						#TODO
					end
				else
					currentSection[:SymbolTable][pack[:Label]]=currentSection[:LocCtr]
				end
				
			end
			#detect whether 'X' appear
			if(result[:Operand])
				pack[:Operand]=result[:Operand].split(/[\s,]+/)
				if(pack[:Operand].last=='X'&&pack[:Operand].size>1)
					pack[:Operand].delete('X')
					pack[:XRegUsed]=true
				end
			else
				pack[:Operand]=[]
			end
			pack[:Operator]=result[:Operator]
			#distinct directive and mnemonic
			if(Directives.include?(result[:Operator].to_sym))
				return ProcDirective.call(pack)
			else
				return ProcMnemonic.call(pack)
			end
		end
		#no operator found
		ErrorAction.call(pack[:Line],-7)
	}

	SetFirstLine=->(pack){
        currentSection[:HeaderRecord]<< 'H'
        currentSection[:HeaderRecord]<< '%s'%pack[:Name]
		for i in 0...6-pack[:Name].size
			currentSection[:HeaderRecord]<< ' '
		end
        currentSection[:HeaderRecord]<< '%06X'%pack[:StartAddress]
    }
	GetFirstLine=->(pack){
        line=STDIN.gets
        #detect improper header format
        if(!line.match(RegExps[:Header]))
            ErrorAction.call(pack[:Line],-2)
        end
        #detect line marked
        ($1=="") or Line[pack[:Line]]=$1
        #detect whether name over-length
        maxStringSize=6
        pack[:Name]=$2
        if(pack[:Name].size>maxStringSize)
            ErrorAction.call(pack[:Line],-3)
		elsif(pack[:Name].size==0)
			WarningAction.call(pack[:Line],-1)
			pack[:Name]='NONAME'
        end
        #set start adderess
        pack[:StartAddress]=$3.to_i(16)

		#create first section
		currentName=pack[:Name]
		currentSection=(Sections[currentName]=CreateSection.call(pack))
    }
	ProcFirstLine=->(pack){
		GetFirstLine.call(pack)
		SetFirstLine.call(pack)
		return ProcMiddle
	}
}
init=->(){
    initMnemonicList.call()
    initDirectives.call()
    initRegExps.call()
    initArgNumTable.call()
    initFormatTable.call()
    initRegisterTable.call()
    initProcs.call()
    initLineConvTable.call()
	initOffsetTable.call()
}
main=->(){
    fileLineCount=1
    #proccess first line
    action=ProcFirstLine
    while(true)
        pack={Line: fileLineCount}
        action=action.call(pack)
        #move to next line
        fileLineCount+=1
    end
}
init.call()
main.call()