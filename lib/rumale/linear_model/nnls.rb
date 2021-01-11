# frozen_string_literal: true

require 'lbfgsb'

require 'rumale/base/base_estimator'
require 'rumale/base/regressor'

module Rumale
  module LinearModel
    # NNLS is a class that implements non-negative least squares regression.
    # NNLS solves least squares problem under non-negative constraints on the coefficient using L-BFGS-B method.
    #
    # @examples
    #   estimator = Rumale::LinearModel::NNLS.new(reg_param: 1e-2, random_seed: 1)
    #   estimator.fit(training_samples, traininig_values)
    #   results = estimator.predict(testing_samples)
    #
    class NNLS
      include Base::BaseEstimator
      include Base::Regressor

      # Return the weight vector.
      # @return [Numo::DFloat] (shape: [n_outputs, n_features])
      attr_reader :weight_vec

      # Return the bias term (a.k.a. intercept).
      # @return [Numo::DFloat] (shape: [n_outputs])
      attr_reader :bias_term

      # Returns the number of iterations when converged.
      # @return [Integer]
      attr_reader :n_iter

      # Return the random generator for initializing weight.
      # @return [Random]
      attr_reader :rng

      # Create a new regressor with non-negative least squares method.
      #
      # @param reg_param [Float] The regularization parameter.
      # @param fit_bias [Boolean] The flag indicating whether to fit the bias term.
      # @param bias_scale [Float] The scale of the bias term.
      # @param max_iter [Integer] The maximum number of epochs that indicates
      #   how many times the whole data is given to the training process.
      # @param tol [Float] The tolerance of loss for terminating optimization.
      #   If solver = 'svd', this parameter is ignored.
      # @param verbose [Boolean] The flag indicating whether to output loss during iteration.
      # @param random_seed [Integer] The seed value using to initialize the random generator.
      def initialize(reg_param: 1.0, fit_bias: true, bias_scale: 1.0,
                     max_iter: 1000, tol: 1e-4, verbose: false, random_seed: nil)
        check_params_numeric(reg_param: reg_param, bias_scale: bias_scale, max_iter: max_iter, tol: tol)
        check_params_boolean(fit_bias: fit_bias, verbose: verbose)
        check_params_numeric_or_nil(random_seed: random_seed)
        check_params_positive(reg_param: reg_param, max_iter: max_iter)
        @params = method(:initialize).parameters.each_with_object({}) { |(_, prm), obj| obj[prm] = binding.local_variable_get(prm) }
        @params[:random_seed] ||= srand
        @n_iter = nil
        @weight_vec = nil
        @bias_term = nil
        @rng = Random.new(@params[:random_seed])
      end

      # Fit the model with given training data.
      #
      # @param x [Numo::DFloat] (shape: [n_samples, n_features]) The training data to be used for fitting the model.
      # @param y [Numo::DFloat] (shape: [n_samples, n_outputs]) The target values to be used for fitting the model.
      # @return [NonneagtiveLeastSquare] The learned regressor itself.
      def fit(x, y)
        x = check_convert_sample_array(x)
        y = check_convert_tvalue_array(y)
        check_sample_tvalue_size(x, y)

        x = expand_feature(x) if fit_bias?

        n_features = x.shape[1]
        is_single_target = y.ndim == 1
        n_outputs = is_single_target ? 1 : y.shape[1]

        w_init = Rumale::Utils.rand_normal([n_outputs, n_features], @rng.dup).flatten.dup
        bounds = Numo::DFloat.zeros(n_outputs * n_features, 2)
        bounds.shape[0].times { |n| bounds[n, 1] = Float::INFINITY }

        res = {}
        res[:x] = w_init
        res[:n_iter] = 0

        res = Lbfgsb.minimize(
          fnc: method(:nnls_fnc), jcb: true, x_init: w_init, args: [x, y, @params[:reg_param]], bounds: bounds,
          maxiter: @params[:max_iter], factr: @params[:tol] / Lbfgsb::DBL_EPSILON, verbose: @params[:verbose] ? 1 : -1
        )

        @n_iter = res[:n_iter]
        w = is_single_target ? res[:x].dup : res[:x].reshape(n_outputs, n_features).transpose

        if @params[:fit_bias]
          @weight_vec = is_single_target ? w[0...-1].dup : w[0...-1, true].dup
          @bias_term = is_single_target ? w[-1] : w[-1, true].dup
        else
          @weight_vec = w.dup
          @bias_term = is_single_target ? 0 : Numo::DFloat.zeros(y.shape[1])
        end

        self
      end

      # Predict values for samples.
      #
      # @param x [Numo::DFloat] (shape: [n_samples, n_features]) The samples to predict the values.
      # @return [Numo::DFloat] (shape: [n_samples, n_outputs]) Predicted values per sample.
      def predict(x)
        x = check_convert_sample_array(x)
        x.dot(@weight_vec.transpose) + @bias_term
      end

      private

      def nnls_fnc(w, x, y, alpha)
        n_samples, n_features = x.shape
        w = w.reshape(y.shape[1], n_features) unless y.shape[1].nil?
        z = x.dot(w.transpose)
        d = z - y
        loss = (d**2).sum.fdiv(n_samples) + alpha * (w * w).sum
        gradient = 2.fdiv(n_samples) * d.transpose.dot(x) + 2.0 * alpha * w
        [loss, gradient.flatten.dup]
      end

      def expand_feature(x)
        n_samples = x.shape[0]
        Numo::NArray.hstack([x, Numo::DFloat.ones([n_samples, 1]) * @params[:bias_scale]])
      end

      def fit_bias?
        @params[:fit_bias] == true
      end
    end
  end
end
