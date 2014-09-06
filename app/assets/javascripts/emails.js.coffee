# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
jQuery ->
  $('input[value="Send"]').click (eo) ->
    to_value = $("#email_to").val()
    if to_value == "" or to_value == null
      $("#email_to_field").addClass("has-error")
      return false



