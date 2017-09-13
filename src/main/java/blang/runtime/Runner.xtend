package blang.runtime

import blang.core.Model
import blang.core.ModelBuilder
import blang.engines.PosteriorInferenceEngine
import blang.engines.SMC
import blang.inits.Arg
import blang.inits.ConstructorArg
import blang.inits.Creator
import blang.inits.Creators
import blang.inits.DefaultValue
import blang.inits.DesignatedConstructor
import blang.inits.GlobalArg
import blang.inits.experiments.Experiment
import blang.inits.experiments.ParsingConfigs
import blang.inits.parsing.Arguments
import blang.inits.parsing.ConfigFile
import blang.inits.parsing.Posix
import blang.inits.parsing.QualifiedName
import blang.inits.providers.CoreProviders
import blang.io.GlobalDataSourceStore
import blang.mcmc.BuiltSamplers
import blang.mcmc.SamplerBuilder
import blang.runtime.objectgraph.GraphAnalysis
import blang.utils.Parsers
import briefj.run.Results
import ca.ubc.stat.blang.jvmmodel.SingleBlangModelInferrer
import java.io.File
import java.util.Collections
import java.util.Optional
import java.util.Random

class Runner extends Experiment {
  
  Model model
  
  @Arg                   @DefaultValue("SMC")
  PosteriorInferenceEngine engine = new SMC
  
  @Arg               @DefaultValue("false")
  boolean printAccessibilityGraph = false
  
  @GlobalArg
  Observations observations
  
  @Arg(description = "Version of the blang SDK to use (see https://github.com/UBC-Stat-ML/blangSDK/releases), of the form of a git tag x.y.z where x >= 2. If omitted, use the local SDK's 'master' version.")
  public Optional<String> version // Only used when called from Main 
  public static final String VERSION_FIELD_NAME = "version" 
  
  @DesignatedConstructor
  new(
    @ConstructorArg(
      value = "model", 
      description = "The model to run (technically, an inner class builder for it, " + 
        "but the suffix '$Builder' can be skipped)"
    ) ModelBuilder builder
  ) {
    this.model = builder.build()
  } 
  
  /**
   * Two syntaxes:
   * - simplified: just one args, the model, rest is read from config file
   * - standard
   */
  def public static Arguments parseArguments(String ... args) {
    if (useSimplifiedArguments(args)) {
      // try to read in (else empty)
      val File configFile = new File(CONFIG_FILE_NAME)
      val Arguments fromFile = {
        if (configFile.exists) {
          ConfigFile.parse(configFile)
        } else {
          new Arguments(Optional.empty, QualifiedName.root)
        }
      }
      // add the one argument (after fixing it)
      val String modelString = fixModelBuilderArgument(args.get(0))
      fromFile.setOrCreateChild("model", Collections.singletonList(modelString))
      return fromFile
    } else {
      fixModelBuilderArgument(args)
      return Posix.parse(args)
    }
  }
  val public static final String CONFIG_FILE_NAME = "configuration.txt"
  
  
  def private static boolean useSimplifiedArguments(String ... args) {
    return args.size == 1
  }
  
  def static void main(String ... args) {
    val Arguments parsedArgs = parseArguments(args)
    val Creator creator = Creators::empty()
    creator.addFactories(CoreProviders)
    creator.addFactories(Parsers)
    val Observations observations = new Observations
    creator.addGlobal(Observations, observations)
    val GlobalDataSourceStore globalDS = new GlobalDataSourceStore
    creator.addGlobal(GlobalDataSourceStore, globalDS)
    
    val ParsingConfigs parsingConfigs = new ParsingConfigs
    parsingConfigs.setCreator(creator) 
    
    printExplationsIfNeeded(args, parsedArgs, creator)
    
    System::exit(Experiment::start(args, parsedArgs, parsingConfigs))
    
//    System.exit(Experiment::start2(args, parsedArgs, parsingConfigs))  
//     
//    
//    val Optional<Options> options = initModel(creator, parsedArgs) 
//    if (options.present) {
//      val GraphAnalysis graphAnalysis = new GraphAnalysis(options.get().model, observations)
//      if (options.get.printAccessibilityGraph) {
//        graphAnalysis.exportAccessibilityGraphVisualization(Results.getFileInResultFolder("accessibility-graph.dot"))
//        graphAnalysis.exportFactorGraphVisualization(Results.getFileInResultFolder("factor-graph.dot"))
//      }
//      new Runner(options.get, graphAnalysis)
//        .run()
//    } else {
//      if (useSimplifiedArguments(args) && !new File(CONFIG_FILE_NAME).exists) {
//        println("Paste the following into a file called '" + CONFIG_FILE_NAME + "' and uncomment and edit the required missing information:")
//      } else {
//        println("Error(s) in provided arguments. Report:")
//      }
//      println(creator.fullReport)
//    }
  }
  
  def static void printExplationsIfNeeded(String [] rawArguments, Arguments parsedArgs, Creator creator) {
    if (!useSimplifiedArguments(rawArguments)) {
      return
    }
    val boolean parsedSuccessfully = try {
      creator.init(Runner, parsedArgs)
      true
    } catch (Exception e) {
      false
    }
    if (!parsedSuccessfully && !new File(CONFIG_FILE_NAME).exists) {
      println("Paste the following into a file called '" + CONFIG_FILE_NAME + "' and uncomment and edit the required missing information:\n\n")
    }
  }
  
  def static String fixModelBuilderArgument(String string) {
    return string + "$" + SingleBlangModelInferrer.BUILDER_NAME
  }
  def static void fixModelBuilderArgument(String[] strings) {
    for (var int i = 0; i < strings.size; i++) {
      if (strings.get(i).trim == "--model" && 
          i < strings.size - 1 &&
          !strings.get(i+1).contains('$')
      ) {
        strings.set(i+1, fixModelBuilderArgument(strings.get(i+1))) 
      }
    }
  }
  
  val public static final String SAMPLE_FILE = "samples.csv"
  override void run() {
    val GraphAnalysis graphAnalysis = new GraphAnalysis(model, observations)
    if (printAccessibilityGraph) {
      graphAnalysis.exportAccessibilityGraphVisualization(Results.getFileInResultFolder("accessibility-graph.dot"))
      graphAnalysis.exportFactorGraphVisualization(Results.getFileInResultFolder("factor-graph.dot"))
    }
    val BuiltSamplers kernels = SamplerBuilder.build(graphAnalysis)
    println(kernels)
    val SampledModel sampledModel = new SampledModel(graphAnalysis, kernels, new Random(1))
    engine.sampledModel = sampledModel
    engine.performInference
  }
}