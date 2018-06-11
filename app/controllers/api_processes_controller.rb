class ApiProcessesController < ApplicationController

  def login
    if user = User.authenticate(params[:email], params[:password], @account.id)
      @role_level = user.roles.order('role_level desc').first.role_level
      if user.active != true
        respond_error 'Your user account is inactive'
      elsif is_mover? == false
        respond_error 'Not a mover account'
      else
        token = user.allow_token_to_be_used_only_once
        render json: {
            status: :ok,
            user: user,
            token: token
        }
      end
    else
      respond_error 'Invalid email or password'
    end
  end

  def get_move_records
    user_id = @current_user.id
    account_id = @current_user.account_id
    sql = %{select mv.id, mv.move_contract_name, max(cs.stage_num) as stage_id
            from move_records mv
            inner join move_status_email_alerts msea on mv.id = msea.move_record_id
            inner join contact_stages cs on cs.id = msea.contact_stage_id
            inner join move_record_trucks mvt on mvt.move_record_id = mv.id
            where (cs.stage='Lead' or cs.stage = 'Book')
            and mv.account_id = ? and 
            (mv.user_id = ? or mvt.lead = ? or mvt.mover_2 = ? or 
            mvt.mover_3 = ? or mvt.mover_4 = ? or mvt.mover_5 = ? or mvt.mover_6 = ?) 
            GROUP BY mv.id, move_contract_name
          };
    move_records = ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.send(:sanitize_sql_array, [sql, account_id, user_id, user_id, user_id, user_id, user_id, user_id, user_id ]))
    render json: {status: :ok, move_records: move_records}
  end

  def get_move_details
    check_move_record_permissions()
    user_id = @current_user.id
    account_id = @current_user.account_id
    move_record = MoveRecord.where(account_id: @current_user.account_id, id: params[:id]).first
    client = MoveRecordClient.where(account_id: @current_user.account_id, move_record_id: params[:id]).first.client
    location_from = MoveRecordLocationOrigin.where(account_id: @current_user.account_id, move_record_id: params[:id]).first.location
    location_to = MoveRecordLocationDestination.where(account_id: @current_user.account_id, move_record_id: params[:id]).first.location
    move_record_date = MoveRecordDate.where(account_id: @current_user.account_id, move_record_id: params[:id]).first
    @move_record_truck = (truck = MoveRecordTruck.where(account_id: @current_user.account_id, move_record_id: params[:id]).first)

    move_record_cost_hourly = MoveRecordCostHourly.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_packing = MoveRecordPacking.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_other_cost = MoveRecordOtherCost.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_surchage = MoveRecordSurcharge.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_flat_rate = MoveRecordFlatRate.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_discount = MoveRecordDiscount.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_insurance = MoveRecordInsurance.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_fuel_cost = MoveRecordFuelCost.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    # @move_record_payment = MoveRecordPayment.find_by_account_id_and_move_record_id(@current_user.account_id, params[:id])
    stage = MoveStatusEmailAlert.where(account_id: @current_user.account_id, move_record_id: params[:id]).order(contact_stage_id: :desc).first.contact_stage.stage
    #move_messages = MessagesMoveRecordsController.new
    #move_messages.index_messages
    @full_messages = []
    @role_level = @current_user.roles.order('role_level desc').first.role_level
    custom_messages = UserMessagesMoveRecord.where(account_id: @current_user.account_id, user_id: @current_user.id)
    @all_messages = MessagesMoveRecord.where('(account_id = ? and move_record_id = ?) and (user_id in (?) OR id in (?)) ', @current_user.account_id, params[:id], @current_user.id, custom_messages.map { |v| v.messages_move_record_id }).order(created_at: (params[:message_sort].present? ? (params[:message_sort] == 'DESC' ? :asc : :desc) : :desc)).select(:id, :parent_id)

    @all_messages.each do |info_message|
      
      if (info_message.parent_id.blank?)
        @full_messages.push({main: get_move_parent_message(info_message.id), reply: []})
      end
    end
    @full_messages = @full_messages.uniq { |e| e[:main] }
    @full_messages.map! do |all_message, index|
      if all_message[:main].present? and @move_record_truck.truck
        to_users = all_message[:main].user_messages_move_record.map { |v| v.user.name } + all_message[:main].task_messages_move_record.map { |v| v.subtask_staff_group.name } + all_message[:main].email_messages_move_record.map { |v| v.user_id == @move_record_clients[0].client.user_id ? 'Customer' : nil } + all_message[:main].email_messages_move_record.map { |v| v.user_id == @move_record_trucks[0].lead ? 'Driver' : nil }
        all_message[:main].from = all_message[:main].user_id == @move_record_truck.truck.driver ? 'Driver' : all_message[:main].user.name
      else
        all_message[:main].from = all_message[:main].user.name
      end
      all_message
    end
    @can_show_who = false
    render json: {
      status: :ok,
      who: {
        name: @can_show_name_or_street? client.name : false,
        title: @can_show_name_or_street? client.title : false,
        home_phone: @can_show_phones_and_email? client.home_phone : false,
        cell_phone: @can_show_phones_and_email? client.cell_phone : false,
        work_phone: @can_show_phones_and_email? client.work_phone : false,
        email: @can_show_phones_and_email? client.email : false,
        move_type_detail: move_record.move_type_detail,
        move_type: move_record.move_type&.description,
        move_type_alert: move_record.move_type_alert_id,
        move_type_alert_importance: move_record.move_type_alert_importance
        },
      what: {
        cargo_type: move_record.cargo_type_id,
        descriptor: move_record.cargo_descriptor,
        cargo_room: move_record.cargo_room,
        cargo_weight: move_record.cargo_weight,
        cargo_cubic: move_record.cargo_cubic,
        cargo_alert_detail: move_record.cargo_detail,
        cargo_description: move_record.cargo_description,
        cargo_note: move_record.what_note,
        cargo_alert_id: move_record.cargo_alert_id,
        cargo_alert_importance: move_record.cargo_alert_importance
      },
      where: {
        location_from: location_from,
        location_to: location_to,
        location_notes: move_record.where_note
      },
      when: {
        date: move_record_date.move_date&.strftime("%d/%m/%y") || 'TBD',
        time: move_record_date.move_time&.strftime("%H:%M"),
        details: move_record_date,
        note: move_record.when_note
      },
      how: {
        equipment_note: move_record.how_note,
        truck: @move_record_truck.as_json({
                include: [
                  :truck, 
                  { user: { only: [:name, :email] } },
                  { mover2: { only: [:name, :email] } },
                  { mover3: { only: [:name, :email] } },
                  { mover4: { only: [:name, :email] } },
                  { mover5: { only: [:name, :email] } },
                  { mover6: { only: [:name, :email] } },
                ]
              })

      },
      how_much: {
        est_move_time: move_record_date.estimation_time,
        start_time: move_record_cost_hourly.start? ? DateTime.parse(move_record_cost_hourly.start).strftime("%H:%M") : 0,
        detail: move_record_cost_hourly,
        desposit: move_record.deposit,
        payment: move_record.payment
      },
      stage: stage,
      messages: @full_messages.as_json(methods: [:from]),
    }
  end

  def get_messages
    get_personal_messages()
    @full_messages.map! {|msg| 
      msg[:created_at] = msg[:created_at].strftime("%l:%M %P %b %d")
      msg
    }
    render json: {status: :ok, messages: @full_messages}
  end

  def get_staffs
    @all_subtask ||= Rails.cache.fetch("all_subtask_staff_group/#{@current_user.account_id}") do
      SubtaskStaffGroup.where(account_id: @current_user.account_id, mailbox: true, active: true)
    end
    render json: {status: :ok, staffs: @all_subtask}
  end

  def compose_message
    respond_to do |format|
      params[:to].each do |task|
        @message = MessagesTask.new
        @message.account_id = @current_user.account_id
        @message.user_id = @current_user.id
        @message.subtask_staff_group_id = task.gsub('task_', '').to_i
        @message.subject = params[:subject]
        @message.urgent = params[:urgent]
        @message.body = params[:body]
        @message.task_sender_id = params[:task]
        if @message.save
          user_task = StaffTask.where(subtask_staff_group_id: @message.subtask_staff_group_id, account_id: @message.account_id)
          user_task.each do |user|
            u_messages = UserMessagesTask.new
            u_messages.account_id = @message.account_id
            u_messages.user_id = user.user_id
            u_messages.messages_task_id = @message.id
            u_messages.readed = false
            u_messages.save
          end
          params[:file] ||= []
          params[:file].each do |file|
            file = upload_attachment(file)
            attachment = MessagesTaskAttachment.new
            attachment.messages_task_id = @message.id
            attachment.file_path = file[:url]
            attachment.name = file[:name]
            attachment.account_id = @message.account_id
            attachment.save
          end
          params[:forward] ||= []
          params[:forward].each do |file|
            attachment = MessagesTaskAttachment.new
            attachment.messages_task_id = @message.id
            attachment.file_path = file[:url]
            attachment.name = file[:name]
            attachment.account_id = @message.account_id
            attachment.save
          end
        end
        if !@message.blank?
          format.json { render json: {status: :ok} }
        else
          format.json { render json: @message.errors, status: :unprocessable_entity }
        end
      end
    end
  end
  private

  def upload_attachment(file_param)
    name = (rand() * 4).to_s + '_' + Time.now.to_i.to_s + '_' + file_param.original_filename
    return {url: upload_bucket_file(file_param, name, 'mmo-attachments-dev'), name: name}
  end

  def move_record_params
    params[:move_record].permit!.to_h
  end

  def respond_error error
    render json: {status: :fail, error: error}
  end
  
end
