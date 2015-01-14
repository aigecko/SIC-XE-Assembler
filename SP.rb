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
        SIO:     0xF0,        SSK:     0xEC,        STA:      0x00,        STB:     0x78,
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

		SymbolTable: Hash.new()
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
		for sym,val in currentSection[:SymbolTable]
			puts "%s: %X"%[sym,val]
		end
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
		for sym,val in currentSection[:SymbolTable]
			puts "%s: %X"%[sym,val]
		end
		for name,section in Sections
			puts section[:HeaderRecord]
			for code in section[:TextArray].values
				if(code.class==String)
					puts code
				else
					puts "%X"%code
				end
			end
			puts section[:TextRecord]
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

    ProcMnemonic=->(pack){
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
		pack[:Operator]=pack[:Operator].to_sym
		#generate binary code
		if(pack[:Operand].size==0)
			#no operand , direct output binary
			currentSection[:TextArray][currentSection[:LocCtr]]=
				MnemonicList[pack[:Operator]]
		elsif(pack[:Operand].size==2)
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
				#TODO
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
			if(currentSection[:SymbolTable].keys.include? pack[:Label])
				ErrorAction.call(pack[:Line],-6)
			end
			if(pack[:Label])
				currentSection[:SymbolTable][pack[:Label]]=currentSection[:LocCtr]
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