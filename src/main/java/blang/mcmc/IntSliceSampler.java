package blang.mcmc;

import java.util.List;
import bayonet.distributions.Random;

import blang.core.LogScaleFactor;
import blang.core.WritableIntVar;
import blang.distributions.Generators;


public class IntSliceSampler implements Sampler
{
  @SampledVariable
  protected WritableIntVar variable;
  
  @ConnectedFactor
  protected List<LogScaleFactor> numericFactors;
  
  public static IntSliceSampler build(WritableIntVar variable, List<LogScaleFactor> numericFactors)
  {
    IntSliceSampler result = new IntSliceSampler();
    result.variable = variable;
    result.numericFactors = numericFactors;
    return result;
  }
  
  public void execute(Random random)
  {
    // sample slice
    final double logSliceHeight = nextSliceHeight(random); // log(Y) in Neal's paper
    final int oldState = variable.intValue();        // x0 in Neal's paper
   
    // doubling procedure
    int 
      leftProposalEndPoint = oldState, // L in Neal's paper
      rightProposalEndPoint = leftProposalEndPoint + 1;          // R in Neal's paper
    
    // convention: left is inclusive, right is exclusive
    
    while (logSliceHeight < logDensityAt(leftProposalEndPoint) || logSliceHeight < logDensityAt(rightProposalEndPoint - 1)) 
      if (random.nextBernoulli(0.5))
      {
        leftProposalEndPoint += - (rightProposalEndPoint - leftProposalEndPoint);
        if (leftProposalEndPoint == Double.NEGATIVE_INFINITY)
          throw new RuntimeException(INFINITE_SLICE_MESSAGE);
      }
      else
      {
        rightProposalEndPoint += rightProposalEndPoint - leftProposalEndPoint;
        if (rightProposalEndPoint == Double.POSITIVE_INFINITY)
          throw new RuntimeException(INFINITE_SLICE_MESSAGE);
      }
    
    // shrinkage procedure
    int 
      leftShrankEndPoint = leftProposalEndPoint,   // bar L in Neal's paper
      rightShrankEndPoint = rightProposalEndPoint; // bar R in Neal's paper
    while (true) 
    {
      final int newState = Generators.discreteUniform(random, leftShrankEndPoint, rightShrankEndPoint); // x1 in Neal's paper
      if (logSliceHeight <= logDensityAt(newState) && accept(oldState, newState, logSliceHeight, leftProposalEndPoint, rightProposalEndPoint))
      {
        variable.set(newState);
        return;
      }
      if (newState < oldState)
        leftShrankEndPoint = newState + 1;
      else
        rightShrankEndPoint = newState;
    }
  }
  
  private boolean accept(int oldState, int newState, double logSliceHeight, int leftProposalEndPoint, int rightProposalEndPoint) 
  {
    boolean differ = false; // D in Neal's paper; whether the intervals generated by new and old differ; used for optimization
    while (rightProposalEndPoint - leftProposalEndPoint > 1) // 1.1 factor to cover for numerical round offs
    {
      final int middle = (leftProposalEndPoint + rightProposalEndPoint) / 2; // M in Neal's paper
      if ((oldState <  middle && newState >= middle) || 
          (oldState >= middle && newState < middle))
        differ = true;
      if (newState < middle)
        rightProposalEndPoint = middle;
      else
        leftProposalEndPoint = middle;
      if (differ && logSliceHeight >= logDensityAt(leftProposalEndPoint) && logSliceHeight >= logDensityAt(rightProposalEndPoint - 1))
        return false;
    }
    return true;
  }

  private double nextSliceHeight(Random random)
  {
    return logDensity() - Generators.unitRateExponential(random); 
  }
  
  private double logDensityAt(int x)
  {
    variable.set(x);
    return logDensity();
  }
  
  private double logDensity() {
    double sum = 0.0;
    for (LogScaleFactor f : numericFactors)
      sum += f.logDensity();
    if (Double.isNaN(sum))
      throw new RuntimeException();
    return sum;
  }
  
  public boolean setup() 
  {
    return true;
  }
  
  private static final String INFINITE_SLICE_MESSAGE = "Slice diverged to infinity. "
      + "Possible cause is that a variable has no distribution attached to it, i.e. the model is improper.";
}