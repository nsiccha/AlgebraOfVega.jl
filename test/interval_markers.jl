using Test, AlgebraOfVega

function marker_nodes(x)
    x isa AbstractDict && return [x; reduce(vcat, marker_nodes.(collect(values(x))); init=Any[])]
    x isa AbstractVector && return reduce(vcat, marker_nodes.(x); init=Any[])
    Any[]
end

@testset "interval markers retain categorical estimates" begin
    draws = (value=[0.,2.,10.,12.,100.,102.,110.,112.],
        subject=fill("S",8), dose=fill("5 mg",8),
        sex=repeat(["Female","Female","Male","Male"],2),
        panel=repeat(["A","B"];inner=4))
    for analysis in (pointinterval(), gradient_interval(), dotinterval()), vertical in (false,true)
        # All other keys coincide within each facet: dropping marker would pool sexes.
        m = vertical ? mapping(:subject,:value; color=:dose, marker=:sex=>sorter(["Male","Female"])=>"Sex",col=:panel) :
            mapping(:value; y=:subject,color=:dose,marker=:sex=>sorter(["Male","Female"])=>"Sex",col=:panel)
        a = vertical ? (analysis.transformation isa AlgebraOfVega.PointIntervalAnalysis ? pointinterval(orientation=:vertical) :
            analysis.transformation isa AlgebraOfVega.GradientIntervalAnalysis ? gradient_interval(orientation=:vertical) : dotinterval(orientation=:vertical)) : analysis
        vl=to_vegalite(data(draws)*m*a)
        nodes=marker_nodes(vl)
        shapes=[n["encoding"]["shape"] for n in nodes if haskey(n,"encoding") && haskey(n["encoding"],"shape")]
        @test length(shapes)==1
        @test shapes[1]["field"]=="sex"
        @test shapes[1]["title"]=="Sex"
        @test shapes[1]["sort"]==["Male","Female"]
        estimates=[n for n in nodes if haskey(n,"__point__")]
        @test sort([n["__point__"] for n in estimates])==[1.,11.,101.,111.]
        @test Set((n["panel"],n["sex"]) for n in estimates)==Set([("A","Female"),("A","Male"),("B","Female"),("B","Male")])
    end
    pre=(median=[1.,11.],lo=[0.,10.],hi=[2.,12.],subject=["S1","S2"],sex=["Female","Male"],dose=["5 mg","45 mg"])
    for vertical in (false,true)
        m=vertical ? mapping(:subject,:median;marker=:sex=>"Sex",color=:dose) : mapping(:median;y=:subject,marker=:sex=>"Sex",color=:dose)
        vl=to_vegalite(data(pre)*m*pointinterval(bands=[:lo=>:hi],orientation=vertical ? :vertical : :horizontal))
        @test vl["data"]["values"]==AlgebraOfVega.table_to_rows(pre)
        @test vl["layer"][end]["encoding"]["shape"]["field"]=="sex"
        @test !haskey(vl["layer"][1]["encoding"],"shape")
        @test !haskey(vl["layer"][end]["encoding"],"color") # fixed white fill retained
        sc=scales(Marker=(categories=["Female","Male","Not reported"],palette=["circle","square","diamond"]))
        scaled=to_vegalite(data(pre)*m*pointinterval(bands=[:lo=>:hi],orientation=vertical ? :vertical : :horizontal),sc)
        @test scaled["layer"][end]["encoding"]["shape"]["scale"]["domain"]==["Female","Male","Not reported"]
        @test scaled["layer"][end]["encoding"]["shape"]["scale"]["range"]==["circle","square","diamond"]
        @test !haskey(scaled["layer"][1]["encoding"],"shape")
    end
end
