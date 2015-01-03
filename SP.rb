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
        :Indirect=> /(@[\w_]*)/, #detect and get whether indirect adressing
        :Immediate=> /#[\w_]*/, #detect and get whether immediate addressing        
        :LiteralString=> /=C'(\w*)'/, #get string part of a literal
        :LiteralHex=> /=X'[A-Fa-f0-9]*'/ #get hex digit part of a literal
    }	
	RegExps[:Middle]=Regexp.new(
		'^(\s*(?<Line>\d*))?'+ #line number part
		'\s*((?<Label>\w+)\s+)?'+ #label part
		'(?<Operator>\+?'+ #operator
		"(#{(MnemonicList.keys+Directives).sort{|s| -s.length}.join('|')}))"+ #operator part
		'(\s+(?<Operand>(\S+(\s*,\s*\S+)?)))?'+ #operand part		
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
		TextArray: Array.new(),
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
            "Define a Mnemonic or Dirctive as a Label is illegal"
        when -5
            "Unknown StartPoint after 'END'"
		when -6
		
		when -7
			"Operator unfound"
        else
            "Runtime Error"
        end
        )
        STDERR.puts(
		if(Line[fileLineCount])
			"At line code-mode: #{Line[fileLineCount]}"
		else
			"At line text-mode: #{fileLineCount}"
		end
		)
        exit(errno)
    }
    ExitAction=->(){ exit(0) }
    FinalOutput=->(pack){
        print headerRecord
        print textRecord
        print endRecord
		ExitAction.call
    }
	
	ProcMnemonic=->(){}
	ProcDirective=->(){}
	ProcDefineSymbol=->(){}
	ProcProgramBlock=->(){}
	ProcContralSection=->(){}
	
	SetLastLine=->(pack){
		#headerRecord<< "%06d" % (proLocCtr-startLoc)
		
        #endRecord<< 'E'
		#endRecord<< "%06d"%startLoc
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
	
    SetMidLine=->(pack){
        textRecord<< 'T'
        return GetMidLine
    }
    GetMidLine=->(pack){
        line=STDIN.gets
        # if END appeared
        if(line=~RegExps[:End])            
            # set line number
            ($1=="") or Line[pack[:Line]]=$1
            # set start point
            pack[:StartPoint]=($2!="")? $2.to_sym : nil
            return GetLastLine.call(pack)
        end
		
        #ignore comment
        (line.match()) and return GetMidLine
        #convert line number into inner format
        line=line.match(RegExps[:Line])[2]
        Line[line]= (($1=='')? nil : $1)
        #get the first token
        line.match(RegExps[:FirstToken])
    
        mnemonic=directive=label=comment=other=nil        
        #make match pattern familiar
        plusCharacter=$1
        firstToken=$2.to_sym
        other=$3
                
        #detect format 4
        useFormat4= (plusCharacter=='+') ? true: false
        #get tokens
        if(MnemonicList.keys.include?(firstToken))
            #opcode
            mnemonic=firstToken
        elsif(Directives.include?(firstToken))
            #directives
            directive=firstToken
        else
            #label            
            label=firstToken
            SymbolTable[label]=proLocCtr
            #make match pattern familiar
            other.match(RegExps[:FirstToken])
            firstToken=$2.to_sym
            other=$3
            #get next token
            if(MnemonicList.keys.include?(firstToken))
                #opcode after label
                mnemonic=firstToken
            elsif(Directives.include?(firstToken))
                #directives after label
                directive=firstToken
            else
                #ERROR!                                
                ErrorAction.call(fileLineCount,-2)
            end
        end
        
        #get arguments
        argList=[]
        ArgNum[mnemonic||directive].times{
            other.match(RegExps[:Argument])
            argList<<$1
            other=$2
        }
        xRegUsed=false
        if other.match(RegExps[:XRegUsed])
            comment=$1
            xRegUsed=true
        else
            comment=other.match(RegExps[:LastPart])[0]
        end
        
        #create package
        pack={
            Label: label,
            Format: (mnemonic and (useFormat4)?4:(FormatTable[mnemonic])),
            Mnemonic: mnemonic,
            Directive: directive,
            ArgList: argList,
            XRegUsed: xRegUsed#,
            #Line: fileLineCount
        }
        return SetMidLine.call(pack)
    }    
	ProcMiddle=->(pack){
		line=STDIN.gets
        #if END appeared
        if(line=~RegExps[:End])            
            #set line number
            ($1=="") or Line[pack[:Line]]=$1
            #set start point
            pack[:StartPoint]=($2!="")? $2.to_sym : nil
            return ProcLastLine.call(pack)
        end
		#ignore comment
		if(line=~RegExps[:Comment])
			return ProcMiddle
		end
		
		if(result=line.match(RegExps[:Middle]))			
			pack[:Line]=result[:Line]
			pack[:Label]=result[:Label]
			pack[:Operator]=result[:Operator]
			if(result[:Operand]) 
				pack[:Operand]=result[:Operand].split(/[\s,]*/)
			else
				pack[:Operand]=[]
			end
		else
			puts line
			ErrorAction.call(pack[:Line],-7)
		end
		return ProcMiddle		
	}	
	
	SetFirstLine=->(pack){
        currentSection[:HeaderRecord]<< 'H'
        currentSection[:HeaderRecord]<< '%s'%pack[:Name]
		for i in 0...6-pack[:Name].size
			currentSection[:HeaderRecord]<< ' '
		end
        currentSection[:HeaderRecord]<< '%06d'%pack[:StartAddress]
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
        pack[:StartAddress]=$3.to_i
		
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
    pack={Line: fileLineCount}
    action=ProcFirstLine.call(pack)
    while(true)
        pack={Line: fileLineCount}
        action=action.call(pack)
        
        #move to next line
        fileLineCount+=1		
    end
}
init.call()
main.call()
